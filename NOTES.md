# MCP Mug — Learning Notes

## MCP Tools

**What it is:**
An MCP "tool" is a unit of functionality an MCP server exposes to a client (like Claude, or MCP Inspector). It's roughly the MCP equivalent of a single Rails controller action — it has a name, a description, a declared input shape (JSON Schema), and a handler that runs and returns a result. The client discovers available tools via `tools/list` and invokes one via `tools/call`.

**Basic example:**
```ruby
class ExampleTool < MCP::Tool
  description "Echoes back a message"
  input_schema(
    properties: { message: { type: "string" } },
    required: ["message"]
  )

  def self.call(message:, server_context:)
    MCP::Tool::Response.new([{ type: "text", text: "You said: #{message}" }])
  end
end
```

**Real example (this project):**
```ruby
class ListMugsTool < MCP::Tool
  description "List all available mugs with their size, price, and stock"
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    mugs = Mug.all.map { |m| { size: m.size, price_cents: m.price_cents, stock: m.stock } }
    MCP::Tool::Response.new([{ type: "text", text: mugs.to_json }])
  end
end
```
`CreateOrderTool` (in `app/tools/create_order_tool.rb`) is the mutating counterpart — it validates input against `input_schema`, checks stock, then creates an `Order` inside a DB transaction.

**Key rules:**
- `input_schema` is JSON Schema — `properties` + `required` — and is validated by the gem before your `call` method ever runs.
- `self.call` receives your declared inputs as keyword args, plus `server_context:` always (a hash for passing request-scoped data like the authenticated user — currently empty, will carry identity once auth is added).
- Must return an `MCP::Tool::Response.new([...])` — an array of content blocks (`{ type: "text", text: "..." }` for plain text). If `text` is structured data, `.to_json` it yourself — the content block expects a string.
- A `NameError`/`ArgumentError` raised inside `call` doesn't crash the Rails process — the gem rescues it and returns a JSON-RPC error object (`code: -32603`, `message: "Internal error"`, `data: "<actual exception message>"`) as part of a normal HTTP 200 response. Always check the `data` field for the real cause, not just the code.
- Local variables assigned only inside a block (e.g. inside `transaction do...end`) aren't visible outside the block unless pre-declared (`order = nil`) before it — a plain Ruby scoping rule, not MCP-specific, but easy to trip on inside a tool's `call` method.

**Interview questions:**
1. How does an MCP tool's `input_schema` relate to strong parameters in a traditional Rails controller — what's the same, what's different?
2. Why does a Ruby exception inside a tool's `call` method result in an HTTP 200 with a JSON-RPC error body, instead of Rails' normal 500 error page?
3. What is `server_context` for, and how will it be used differently once JWT auth is added in Phase 2?

## MCP Server + Transport (controller-based)

**What it is:**
`MCP::Server` bundles a set of tools (and optionally prompts/resources) under a server name. `StreamableHTTPTransport` is the Rack-level adapter that speaks the MCP wire protocol (JSON-RPC over HTTP, plus SSE) and dispatches incoming requests to the right tool. We chose the **controller approach**: build a new `MCP::Server` per HTTP request inside `McpController#create`, rather than mounting one static instance in `routes.rb`.

**Basic example:**
```ruby
server = MCP::Server.new(name: "example", tools: [ExampleTool])
transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
status, headers, body = transport.handle_request(request)
```

**Real example (this project) — `app/controllers/mcp_controller.rb`:**
```ruby
class McpController < ActionController::API
  def create
    server = MCP::Server.new(
      name: "mcp_mug",
      tools: [ListMugsTool, CreateOrderTool],
      server_context: {}
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    status, headers, body = transport.handle_request(request)
    render(json: body.first, status: status, headers: headers)
  end
end
```
Routed via (`config/routes.rb`):
```ruby
match "/mcp", to: "mcp#create", via: [:get, :post, :delete]
```

**Key rules:**
- The transport needs **all three** HTTP methods routed: `POST` (JSON-RPC calls), `GET` (opening an SSE stream), `DELETE` (session cleanup). Only routing `POST` causes the client's SSE connection attempt to 500/fail with no useful Rails-side error.
- Controller-approach (vs. mounting once in `routes.rb`) lets `server_context` vary per request — required once we pull `current_user`/JWT claims into it in Phase 2.
- `stateless: true` treats every request independently (no persisted MCP session across requests) — simpler for local dev/learning; a stateful session would use an `Mcp-Session-Id` and require sticky sessions in production.
- The transport holds session/SSE state in memory, so it requires a single Puma process (`workers 0`) — not an issue in dev.

**Interview questions:**
1. Why did we choose "build a new `MCP::Server` per request" over mounting a single server instance in `routes.rb`?
2. What would break if we only routed `POST /mcp` and not `GET`/`DELETE`?
3. What's the tradeoff of `stateless: true` vs. a stateful MCP session, and why doesn't it matter yet for this project?

## OAuth 2.1 Protected Resource Metadata (RFC 9728)

**What it is:**
A standardized, unauthenticated `GET /.well-known/oauth-protected-resource` endpoint that lets an MCP client discover *where to get a token* before it has one. When a client hits a protected endpoint without a token, the server responds `401` with a `WWW-Authenticate` header pointing at this metadata URL — the client then fetches it (no auth required, it's public) to learn the resource's identity and which authorization server(s) issue valid tokens for it.

**Basic example (response body):**
```json
{
  "resource": "http://localhost:3000/mcp",
  "authorization_servers": ["https://orderly-beacon-65-staging.authkit.app"],
  "bearer_methods_supported": ["header"]
}
```

**Real example — `app/controllers/well_known_controller.rb`:**
```ruby
def oauth_protected_resource
  render json: {
    resource: "http://localhost:3000/mcp",
    authorization_servers: [AUTHKIT_DOMAIN],
    bearer_methods_supported: ["header"]
  }
end
```
Plus two backward-compatibility proxies we had to add (mirroring AuthKit's own discovery docs from our domain), because some clients skip the newer spec's `authorization_servers` field and instead try these paths directly on the *resource server's own domain*:
```ruby
def oauth_authorization_server
  render json: Rails.cache.fetch("authkit_authorization_server_metadata", expires_in: 1.hour) do
    Net::HTTP.get(URI("#{AUTHKIT_DOMAIN}/.well-known/oauth-authorization-server"))
  end
end
```
(`openid_configuration` follows the identical pattern.)

**Key rules:**
- `resource` must exactly match the resource indicator configured in WorkOS dashboard (Connect → Configuration → MCP resource indicators) — this becomes the token's `aud` claim.
- This endpoint must stay **unauthenticated** — a client without a token needs to be able to read it to find out how to *get* a token. Protecting it would create a chicken-and-egg deadlock.
- Real-world clients vary in which discovery doc they trust first (`oauth-protected-resource`'s `authorization_servers` field vs. directly guessing `oauth-authorization-server`/`openid-configuration` on the resource server's own domain) — supporting all three paths is what actually got our flow working end-to-end.
- `Net::HTTP` needs `require "net/http"` explicitly in a minimal Rails API app — it's not autoloaded like ActiveRecord/ActionController classes are.

**Interview questions:**
1. Why must `/.well-known/oauth-protected-resource` be reachable without authentication, when everything else in this app requires a valid token?
2. What's the difference between `oauth-protected-resource` metadata (RFC 9728) and `oauth-authorization-server` metadata — who serves each one, and what does each tell the client?
3. Why did we need to proxy AuthKit's `oauth-authorization-server` and `openid-configuration` documents from our own domain instead of just relying on the `authorization_servers` field in our protected-resource metadata?

## JWT Verification with JWKS

**What it is:**
Verifying a bearer token means checking three independent things: (1) the signature is valid — i.e. it was actually signed by AuthKit's private key, verified against AuthKit's *public* key fetched from their JWKS endpoint; (2) `iss` (issuer) matches AuthKit's domain exactly; (3) `aud` (audience) matches our resource URL exactly. All three must pass — this is the Rails-app equivalent of `authenticate_user!`, except checking a signed, stateless token instead of a server-side session.

**Basic example:**
```ruby
JWT.decode(token, nil, true, algorithms: ["RS256"], jwks: jwks_set)
```

**Real example — `app/services/authkit_token_verifier.rb`:**
```ruby
class AuthkitTokenVerifier
  ISSUER = "https://orderly-beacon-65-staging.authkit.app"
  JWKS_URI = "https://orderly-beacon-65-staging.authkit.app/oauth2/jwks"
  AUDIENCE = "http://localhost:3000/mcp"

  def self.verify(token)
    payload, _header = JWT.decode(
      token, nil, true,
      algorithms: ["RS256"], iss: ISSUER, verify_iss: true,
      aud: AUDIENCE, verify_aud: true, jwks: jwks
    )
    payload
  rescue JWT::DecodeError => e
    raise InvalidToken, e.message
  end

  def self.jwks
    Rails.cache.fetch("authkit_jwks", expires_in: 1.hour) do
      JWT::JWK::Set.new(JSON.parse(Net::HTTP.get(URI(JWKS_URI))))
    end
  end
end
```
Wired into `McpController` as a `before_action`, mirroring the shape of a Rails `authenticate_user!`:
```ruby
before_action :authenticate!

def authenticate!
  token = request.headers["Authorization"]&.delete_prefix("Bearer ")
  return unauthorized! if token.blank?
  @token_payload = AuthkitTokenVerifier.verify(token)
rescue AuthkitTokenVerifier::InvalidToken
  unauthorized!
end

def unauthorized!
  response.set_header("WWW-Authenticate", %(Bearer resource_metadata="http://localhost:3000/.well-known/oauth-protected-resource"))
  render json: { error: "unauthorized" }, status: :unauthorized
end
```
The decoded `payload["sub"]` (the WorkOS user ID) then flows into `server_context: { user_id: @token_payload["sub"] }`, which `CreateOrderTool` reads instead of hardcoding `"anonymous"`.

**Key rules:**
- JWKS (public signing keys) are fetched over the network and cached (`Rails.cache`, 1 hour) — never re-fetched on every request, same reasoning as caching any slow-changing external API response.
- `iss`/`aud` checks matter even when the signature is valid — without them, a legitimately-signed token issued for a *different* AuthKit-protected app could be replayed against our resource.
- Calling `render`/setting a halting response inside a `before_action` stops the filter chain automatically — identical to any other Rails `before_action` pattern.
- `Net::HTTP` again needs an explicit `require "net/http"`.

**Interview questions:**
1. Why do we verify both the token's signature *and* its `iss`/`aud` claims — isn't a valid signature enough to trust the token?
2. Where does `server_context[:user_id]` actually come from, end to end — trace it from the HTTP header through to the `Order` record?
3. What's the Rails-session equivalent of "the filter chain halts when `unauthorized!` renders a response inside `before_action`"?
