# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"

class Braintrust::Server::Handlers::HealthTest < Minitest::Test
  def test_returns_200
    handler = Braintrust::Server::Handlers::Health.new
    status, _, _ = handler.call({})

    assert_equal 200, status
  end

  def test_returns_json_content_type
    handler = Braintrust::Server::Handlers::Health.new
    _, headers, _ = handler.call({})

    assert_equal "application/json", headers["content-type"]
  end

  def test_returns_status_ok
    handler = Braintrust::Server::Handlers::Health.new
    _, _, body = handler.call({})

    parsed = JSON.parse(body.first)
    assert_equal "ok", parsed["status"]
  end
end
