# frozen_string_literal: true

module Braintrust
  module Server
    module Rack
      # Builds the Rack middleware stack for the eval server.
      class App
        def self.build(evaluators: {}, auth: :clerk_token)
          router = Router.new
          router.add("GET", "/", Handlers::Health.new)
          list_handler = Handlers::List.new(evaluators)
          router.add("GET", "/list", list_handler)
          router.add("POST", "/list", list_handler)
          router.add("POST", "/eval", Handlers::Eval.new(evaluators))

          auth_strategy = resolve_auth(auth)

          app = router
          app = Middleware::Auth.new(app, strategy: auth_strategy)
          Middleware::Cors.new(app)
        end

        def self.resolve_auth(auth)
          case auth
          when :none
            Auth::NoAuth.new
          when :clerk_token
            Auth::ClerkToken.new
          else
            auth
          end
        end

        private_class_method :resolve_auth
      end
    end
  end
end
