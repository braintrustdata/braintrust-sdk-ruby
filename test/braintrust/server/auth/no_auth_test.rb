# frozen_string_literal: true

require "test_helper"

module Braintrust
  module Server
    module Auth
      class NoAuthTest < Minitest::Test
        def setup
          skip_unless_server!
        end

        def test_authenticate_returns_truthy
          auth = NoAuth.new
          assert auth.authenticate({})
        end

        def test_authenticate_ignores_env
          auth = NoAuth.new
          assert auth.authenticate({"HTTP_AUTHORIZATION" => "Bearer anything"})
        end
      end
    end
  end
end
