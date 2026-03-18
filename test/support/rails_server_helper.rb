# Try to load Rails engine dependencies.
RAILS_SERVER_AVAILABLE = begin
  require "rack/test"
  require "action_controller"
  require "action_dispatch"
  require "rails"
  require "braintrust/server/rails"
  true
rescue LoadError
  false
end

if RAILS_SERVER_AVAILABLE
  # Create a minimal Rails application for engine integration tests.
  # Guard against being required multiple times.
  unless defined?(BraintrustRailsTestApp)
    class BraintrustRailsTestApp < Rails::Application
      config.eager_load = false
      config.secret_key_base = "braintrust-rails-test-secret-key-abc123456789"
      config.logger = ::Logger.new(nil)
      config.log_level = :fatal

      # Allow any host in tests (Rack::Test uses "example.org" by default)
      config.hosts.clear

      routes.draw do
        mount Braintrust::Contrib::Rails::Engine, at: "/"
      end

      initialize!
    end
  end
end

module Test
  module Support
    module RailsServerHelper
      def skip_unless_rails_server!
        skip "Rails not available (run with: bundle exec appraisal rails-server rake test)" unless RAILS_SERVER_AVAILABLE
      end

      # The engine itself as a Rack app — use for controller integration tests.
      # Faster and more direct than routing through a full Rails application.
      def rails_engine_app
        Braintrust::Contrib::Rails::Engine
      end

      # The full test Rails application (mounts the engine at /).
      # Use only when you need to verify middleware stack or mounted routing.
      def rails_app
        BraintrustRailsTestApp
      end

      def reset_engine!(evaluators: {}, auth: :none)
        engine = Braintrust::Contrib::Rails::Engine
        engine.config.evaluators = evaluators
        engine.config.auth = auth
        # Clear the long-lived eval service so cached state does not leak across tests.
        engine.instance_variable_set(:@eval_service, nil)
      end
    end
  end
end
