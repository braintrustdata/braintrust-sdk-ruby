# frozen_string_literal: true

require "test_helper"
require_relative "../rails_server_helper"
require "json"

module Braintrust
  module Contrib
    module Rails
      module Server
        class HealthControllerTest < Minitest::Test
          include Braintrust::Contrib::Rails::ServerHelper
          include ::Rack::Test::Methods if defined?(::Rack::Test::Methods)

          def setup
            skip_unless_rails_server!
            reset_engine!(auth: :none)
          end

          def app
            rails_engine_app
          end

          def test_get_root_returns_200
            get "/"
            assert_equal 200, last_response.status
          end

          def test_get_root_returns_json_content_type
            get "/"
            assert_match "application/json", last_response.content_type
          end

          def test_get_root_returns_status_ok
            get "/"
            body = JSON.parse(last_response.body)
            assert_equal "ok", body["status"]
          end
        end
      end
    end
  end
end
