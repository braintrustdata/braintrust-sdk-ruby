# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

class Braintrust::Server::Auth::NoAuthTest < Minitest::Test
  def test_authenticate_returns_truthy
    auth = Braintrust::Server::Auth::NoAuth.new
    assert auth.authenticate({})
  end

  def test_authenticate_ignores_env
    auth = Braintrust::Server::Auth::NoAuth.new
    assert auth.authenticate({"HTTP_AUTHORIZATION" => "Bearer anything"})
  end
end
