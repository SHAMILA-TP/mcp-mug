require "net/http"

class WellKnownController < ActionController::API
  AUTHKIT_DOMAIN = "https://orderly-beacon-65-staging.authkit.app"

  def oauth_protected_resource
    render json: {
      resource: "http://localhost:3000/mcp",
      authorization_servers: [AUTHKIT_DOMAIN],
      bearer_methods_supported: ["header"]
    }
  end

  def oauth_authorization_server
    metadata = Rails.cache.fetch("authkit_authorization_server_metadata", expires_in: 1.hour) do
      Net::HTTP.get(URI("#{AUTHKIT_DOMAIN}/.well-known/oauth-authorization-server"))
    end
    render json: metadata
  end

  def openid_configuration
    metadata = Rails.cache.fetch("authkit_openid_configuration", expires_in: 1.hour) do
      Net::HTTP.get(URI("#{AUTHKIT_DOMAIN}/.well-known/openid-configuration"))
    end
    render json: metadata
  end
end