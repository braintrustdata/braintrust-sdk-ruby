# frozen_string_literal: true

begin
  require "action_controller"
  require "rails/engine"
rescue LoadError
  raise LoadError,
    "Rails (actionpack + railties) is required for the Braintrust Rails server engine. " \
    "Add `gem 'rails'` or `gem 'actionpack'` and `gem 'railties'` to your Gemfile."
end

require "json"
require_relative "../eval"
require_relative "sse"
require_relative "auth/no_auth"
require_relative "auth/clerk_token"
require_relative "middleware/cors"
require_relative "services/list_service"
require_relative "services/eval_service"
require_relative "../contrib/rails/engine"
