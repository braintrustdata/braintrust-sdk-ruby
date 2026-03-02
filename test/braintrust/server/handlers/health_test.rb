# frozen_string_literal: true

require "test_helper"
require "json"

module Braintrust
  module Server
    module Handlers
      class HealthTest < Minitest::Test
        def setup
          skip_unless_server!
        end

        def test_returns_200
          handler = Health.new
          status, _, _ = handler.call({})

          assert_equal 200, status
        end

        def test_returns_json_content_type
          handler = Health.new
          _, headers, _ = handler.call({})

          assert_equal "application/json", headers["content-type"]
        end

        def test_returns_status_ok
          handler = Health.new
          _, _, body = handler.call({})

          parsed = JSON.parse(body.first)
          assert_equal "ok", parsed["status"]
        end
      end
    end
  end
end
