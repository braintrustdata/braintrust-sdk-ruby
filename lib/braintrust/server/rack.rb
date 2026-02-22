# frozen_string_literal: true

begin
  require "rack"
rescue LoadError
  raise LoadError,
    "The 'rack' gem is required for the Braintrust eval server. " \
    "Add `gem 'rack'` to your Gemfile."
end

require "json"
require_relative "../eval"
require_relative "sse"
require_relative "auth/no_auth"
require_relative "auth/clerk_token"
require_relative "middleware/cors"
require_relative "middleware/auth"
require_relative "handlers/health"
require_relative "handlers/list"
require_relative "handlers/eval"
require_relative "router"
require_relative "rack/app"

module Braintrust
  module Server
    module Rack
      # Build the Rack application for the eval server.
      # @param evaluators [Hash<String, Evaluator>] Named evaluators ({ "name" => instance })
      # @param auth [:clerk_token, :none, Object] Auth strategy (default: :clerk_token)
      # @return [#call] Rack application
      def self.app(evaluators: {}, auth: :clerk_token)
        App.build(evaluators: evaluators, auth: auth)
      end
    end
  end
end
