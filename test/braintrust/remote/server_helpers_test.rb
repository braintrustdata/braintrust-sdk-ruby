# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::ServerHelpersTest < Minitest::Test
  # ============================================
  # CORS.allowed_origin? tests
  # ============================================

  def test_cors_allows_nil_origin
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?(nil)
  end

  def test_cors_allows_empty_origin
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("")
  end

  def test_cors_allows_braintrust_dev
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://www.braintrust.dev")
  end

  def test_cors_allows_braintrustdata_com
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://www.braintrustdata.com")
  end

  def test_cors_allows_preview_braintrust_dev
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://my-feature.preview.braintrust.dev")
  end

  def test_cors_allows_vercel_app
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://my-app.vercel.app")
  end

  def test_cors_allows_localhost
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("http://localhost:3000")
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("http://localhost:8080")
  end

  def test_cors_allows_127_0_0_1
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("http://127.0.0.1:3000")
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("http://127.0.0.1:8300")
  end

  def test_cors_rejects_unknown_origin
    refute Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://evil.com")
    refute Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://fake-braintrust.dev")
  end

  def test_cors_allows_whitelisted_origin_from_env
    ENV["WHITELISTED_ORIGIN"] = "https://custom.example.com"
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://custom.example.com")
  ensure
    ENV.delete("WHITELISTED_ORIGIN")
  end

  def test_cors_allows_braintrust_app_url_from_env
    ENV["BRAINTRUST_APP_URL"] = "https://staging.braintrust.dev"
    assert Braintrust::Remote::ServerHelpers::CORS.allowed_origin?("https://staging.braintrust.dev")
  ensure
    ENV.delete("BRAINTRUST_APP_URL")
  end

  # ============================================
  # CORS.headers_for_origin tests
  # ============================================

  def test_cors_headers_for_allowed_origin
    headers = Braintrust::Remote::ServerHelpers::CORS.headers_for_origin("https://www.braintrust.dev")

    assert_equal "https://www.braintrust.dev", headers["Access-Control-Allow-Origin"]
    assert_equal "true", headers["Access-Control-Allow-Credentials"]
    assert headers["Access-Control-Allow-Methods"].include?("POST")
    assert headers["Access-Control-Allow-Headers"].include?("x-bt-auth-token")
  end

  def test_cors_headers_for_disallowed_origin
    headers = Braintrust::Remote::ServerHelpers::CORS.headers_for_origin("https://evil.com")

    assert_equal "*", headers["Access-Control-Allow-Origin"]
    refute headers.key?("Access-Control-Allow-Credentials")
  end

  def test_cors_headers_include_private_network_when_requested
    headers = Braintrust::Remote::ServerHelpers::CORS.headers_for_origin(
      "http://localhost:3000",
      include_private_network: true
    )

    assert_equal "true", headers["Access-Control-Allow-Private-Network"]
  end

  # ============================================
  # Auth.extract_token tests
  # ============================================

  def test_auth_extracts_token_from_x_bt_auth_token
    headers = {"x-bt-auth-token" => "sk-test-key"}
    token = Braintrust::Remote::ServerHelpers::Auth.extract_token(headers)

    assert_equal "sk-test-key", token
  end

  def test_auth_extracts_token_from_rack_style_header
    headers = {"HTTP_X_BT_AUTH_TOKEN" => "sk-rack-key"}
    token = Braintrust::Remote::ServerHelpers::Auth.extract_token(headers)

    assert_equal "sk-rack-key", token
  end

  def test_auth_extracts_token_from_bearer_authorization
    headers = {"Authorization" => "Bearer sk-bearer-key"}
    token = Braintrust::Remote::ServerHelpers::Auth.extract_token(headers)

    assert_equal "sk-bearer-key", token
  end

  def test_auth_returns_nil_when_no_token
    headers = {}
    token = Braintrust::Remote::ServerHelpers::Auth.extract_token(headers)

    assert_nil token
  end

  def test_auth_prefers_x_bt_auth_token_over_bearer
    headers = {
      "x-bt-auth-token" => "sk-direct",
      "Authorization" => "Bearer sk-bearer"
    }
    token = Braintrust::Remote::ServerHelpers::Auth.extract_token(headers)

    assert_equal "sk-direct", token
  end

  # ============================================
  # Auth.extract_org_name tests
  # ============================================

  def test_auth_extracts_org_name
    headers = {"x-bt-org-name" => "my-org"}
    org_name = Braintrust::Remote::ServerHelpers::Auth.extract_org_name(headers)

    assert_equal "my-org", org_name
  end

  def test_auth_extracts_org_name_from_rack_style
    headers = {"HTTP_X_BT_ORG_NAME" => "rack-org"}
    org_name = Braintrust::Remote::ServerHelpers::Auth.extract_org_name(headers)

    assert_equal "rack-org", org_name
  end

  # ============================================
  # Auth.extract_project_id tests
  # ============================================

  def test_auth_extracts_project_id
    headers = {"x-bt-project-id" => "proj-123"}
    project_id = Braintrust::Remote::ServerHelpers::Auth.extract_project_id(headers)

    assert_equal "proj-123", project_id
  end

  # ============================================
  # format_evaluator tests
  # ============================================

  def test_format_evaluator_returns_parameters_and_scores
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters do
        string :model, default: "gpt-4"
      end
      scores [
        Braintrust::Remote::InlineScorer.new("accuracy") { 1.0 }
      ]
    end

    result = Braintrust::Remote::ServerHelpers.format_evaluator(evaluator)

    assert result.key?(:parameters)
    assert result.key?(:scores)
    assert result[:parameters].key?(:model)
    assert_equal "accuracy", result[:scores][0][:name]
  end

  # ============================================
  # format_evaluator_list tests
  # ============================================

  def test_format_evaluator_list_transforms_hash
    evaluators = {
      "Eval1" => Braintrust::Remote::Evaluator.new("Eval1"),
      "Eval2" => Braintrust::Remote::Evaluator.new("Eval2")
    }

    result = Braintrust::Remote::ServerHelpers.format_evaluator_list(evaluators)

    assert result.key?("Eval1")
    assert result.key?("Eval2")
    assert result["Eval1"].key?(:parameters)
    assert result["Eval1"].key?(:scores)
  end

  # ============================================
  # extract_parent tests
  # ============================================

  def test_extract_parent_returns_parent_object
    body = {"parent" => {"object_type" => "playground_logs", "object_id" => "123"}}
    parent = Braintrust::Remote::ServerHelpers.extract_parent(body)

    assert_equal "playground_logs", parent["object_type"]
    assert_equal "123", parent["object_id"]
  end

  def test_extract_parent_returns_nil_when_missing
    body = {"name" => "MyEval"}
    parent = Braintrust::Remote::ServerHelpers.extract_parent(body)

    assert_nil parent
  end

  # ============================================
  # playground_request? tests
  # ============================================

  def test_playground_request_true_when_parent_present
    body = {"parent" => {"object_type" => "playground_logs"}}

    assert Braintrust::Remote::ServerHelpers.playground_request?(body)
  end

  def test_playground_request_false_when_no_parent
    body = {"name" => "MyEval"}

    refute Braintrust::Remote::ServerHelpers.playground_request?(body)
  end
end
