class McpController < ActionController::API
  before_action :authenticate!

  def create
    server = MCP::Server.new(
      name: "mcp_mug",
      tools: [ListMugsTool, CreateOrderTool],
      server_context: { user_id: @token_payload["sub"] }
    )

    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true
    )

    status, headers, body = transport.handle_request(request)
    render(json: body.first, status: status, headers: headers)
  end

  private

  def authenticate!
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")

    if token.blank?
      return unauthorized!
    end

    begin
      @token_payload = AuthkitTokenVerifier.verify(token)
    rescue AuthkitTokenVerifier::InvalidToken
      unauthorized!
    end
  end

  def unauthorized!
    resource_metadata_url = "https://mcp-mug.onrender.com/.well-known/oauth-protected-resource"
    response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{resource_metadata_url}"))
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
