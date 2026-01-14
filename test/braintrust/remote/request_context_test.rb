# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::RequestContextTest < Minitest::Test
  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_required_fields
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    assert_equal "sk-test", ctx.token
    assert_equal "my-org", ctx.org_name
  end

  def test_initializes_with_default_app_origin
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    assert_equal "https://www.braintrust.dev", ctx.app_origin
  end

  def test_initializes_with_custom_app_origin
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org",
      app_origin: "https://staging.braintrust.dev"
    )

    assert_equal "https://staging.braintrust.dev", ctx.app_origin
  end

  def test_initializes_with_project_id
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org",
      project_id: "proj-123"
    )

    assert_equal "proj-123", ctx.project_id
  end

  def test_initializes_as_not_authorized
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    refute ctx.authorized?
    assert_nil ctx.state
    assert_nil ctx.api
  end

  # ============================================
  # authorized? tests
  # ============================================

  def test_authorized_returns_false_initially
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    refute ctx.authorized?
  end

  def test_mark_authorized_sets_flag
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    ctx.mark_authorized!

    assert ctx.authorized?
  end

  # ============================================
  # state and api accessor tests
  # ============================================

  def test_state_accessor
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    mock_state = Object.new
    ctx.state = mock_state

    assert_equal mock_state, ctx.state
  end

  def test_api_accessor
    ctx = Braintrust::Remote::RequestContext.new(
      token: "sk-test",
      org_name: "my-org"
    )

    mock_api = Object.new
    ctx.api = mock_api

    assert_equal mock_api, ctx.api
  end

  # ============================================
  # login! tests (these would need VCR/mocking in real integration tests)
  # ============================================

  # Note: login! actually makes API calls, so we test the error cases here
  # and leave integration testing to actual API tests

  def test_login_requires_token
    ctx = Braintrust::Remote::RequestContext.new(
      token: nil,
      org_name: "my-org"
    )

    # Should raise when trying to login without a token
    # The actual error depends on State implementation
    assert_raises(ArgumentError) do
      ctx.login!
    end
  end
end
