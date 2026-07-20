require "net/http"

class AuthkitTokenVerifier
  ISSUER = "https://orderly-beacon-65-staging.authkit.app"
  JWKS_URI = "https://orderly-beacon-65-staging.authkit.app/oauth2/jwks"
  AUDIENCE = "http://localhost:3000/mcp"

  class InvalidToken < StandardError; end

  def self.verify(token)
    payload, _header = JWT.decode(
      token,
      nil,
      true,
      algorithms: ["RS256"],
      iss: ISSUER,
      verify_iss: true,
      aud: AUDIENCE,
      verify_aud: true,
      jwks: jwks
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