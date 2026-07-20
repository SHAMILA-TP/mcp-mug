Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "pages#home"
  match "/mcp", to: "mcp#create", via: [:get, :post, :delete]
  get "/.well-known/oauth-protected-resource", to: "well_known#oauth_protected_resource"
  get "/.well-known/oauth-authorization-server", to: "well_known#oauth_authorization_server"
  get "/.well-known/openid-configuration", to: "well_known#openid_configuration"
end
