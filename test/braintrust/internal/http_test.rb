# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/http"

class Braintrust::Internal::HttpTest < Minitest::Test
  # -- with_redirects --

  def test_with_redirects_returns_response_on_success
    stub = stub_request(:get, "https://api.example.com/v1/dataset")
      .to_return(status: 200, body: '{"ok":true}')

    uri = URI("https://api.example.com/v1/dataset")
    request = Net::HTTP::Get.new(uri)

    response = Braintrust::Internal::Http.with_redirects(uri, request)

    assert_equal "200", response.code
    assert_equal '{"ok":true}', response.body
  ensure
    remove_request_stub(stub)
  end

  def test_with_redirects_follows_303_to_different_host_with_get
    api_stub = stub_request(:post, "https://api.example.com/btql")
      .to_return(
        status: 303,
        headers: {"Location" => "https://s3.amazonaws.com/bucket/response.jsonl"}
      )

    # Stub only accepts GET with no Authorization - verifies method conversion and auth stripping
    s3_stub = stub_request(:get, "https://s3.amazonaws.com/bucket/response.jsonl")
      .with { |req| req.headers["Authorization"].nil? }
      .to_return(status: 200, body: '{"id":"1"}')

    uri = URI("https://api.example.com/btql")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer secret-token"
    request["Content-Type"] = "application/json"
    request.body = '{"query":"test"}'

    response = Braintrust::Internal::Http.with_redirects(uri, request)

    assert_equal "200", response.code
    assert_equal '{"id":"1"}', response.body
    assert_requested(s3_stub, times: 1)
  ensure
    remove_request_stub(api_stub)
    remove_request_stub(s3_stub)
  end

  def test_with_redirects_preserves_auth_for_same_host
    redirect_stub = stub_request(:get, "https://api.example.com/old")
      .to_return(
        status: 303,
        headers: {"Location" => "https://api.example.com/new"}
      )

    # Stub requires Authorization header - verifies auth is preserved for same host
    target_stub = stub_request(:get, "https://api.example.com/new")
      .with(headers: {"Authorization" => "Bearer secret-token"})
      .to_return(status: 200, body: "ok")

    uri = URI("https://api.example.com/old")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer secret-token"

    Braintrust::Internal::Http.with_redirects(uri, request)

    assert_requested(target_stub, times: 1)
  ensure
    remove_request_stub(redirect_stub)
    remove_request_stub(target_stub)
  end

  def test_with_redirects_307_preserves_method_and_body
    redirect_stub = stub_request(:post, "https://api.example.com/old")
      .to_return(
        status: 307,
        headers: {"Location" => "https://api.example.com/new"}
      )

    # Stub requires POST with matching body and content-type - verifies method/body preservation
    target_stub = stub_request(:post, "https://api.example.com/new")
      .with(body: '{"data":1}', headers: {"Content-Type" => "application/json"})
      .to_return(status: 200, body: "ok")

    uri = URI("https://api.example.com/old")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer secret-token"
    request.body = '{"data":1}'

    Braintrust::Internal::Http.with_redirects(uri, request)

    assert_requested(target_stub, times: 1)
  ensure
    remove_request_stub(redirect_stub)
    remove_request_stub(target_stub)
  end

  def test_with_redirects_raises_on_too_many_redirects
    stubs = (0..5).map { |i|
      stub_request(:get, "https://api.example.com/r#{i}")
        .to_return(
          status: 302,
          headers: {"Location" => "https://api.example.com/r#{i + 1}"}
        )
    }

    uri = URI("https://api.example.com/r0")
    request = Net::HTTP::Get.new(uri)

    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Http.with_redirects(uri, request)
    end

    assert_match(/too many redirects/i, error.message)
  ensure
    stubs.each { |s| remove_request_stub(s) }
  end

  def test_with_redirects_respects_custom_max_redirects
    stubs = (0..2).map { |i|
      stub_request(:get, "https://api.example.com/r#{i}")
        .to_return(
          status: 302,
          headers: {"Location" => "https://api.example.com/r#{i + 1}"}
        )
    }

    uri = URI("https://api.example.com/r0")
    request = Net::HTTP::Get.new(uri)

    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Http.with_redirects(uri, request, max_redirects: 2)
    end

    assert_match(/too many redirects.*max 2/i, error.message)
  ensure
    stubs.each { |s| remove_request_stub(s) }
  end

  def test_with_redirects_raises_on_missing_location_header
    stub = stub_request(:get, "https://api.example.com/missing")
      .to_return(status: 303)

    uri = URI("https://api.example.com/missing")
    request = Net::HTTP::Get.new(uri)

    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Http.with_redirects(uri, request)
    end

    assert_match(/without location header/i, error.message)
  ensure
    remove_request_stub(stub)
  end

  # -- decompress_response! --

  def test_decompress_response_handles_gzip
    original = "hello world"
    gzipped = gzip_string(original)

    stub = stub_request(:get, "https://s3.example.com/data.jsonl.gz")
      .to_return(
        status: 200,
        body: gzipped,
        headers: {"Content-Encoding" => "gzip"}
      )

    uri = URI("https://s3.example.com/data.jsonl.gz")
    request = Net::HTTP::Get.new(uri)
    response = Braintrust::Internal::Http.with_redirects(uri, request)

    Braintrust::Internal::Http.decompress_response!(response)

    assert_equal original, response.body
    assert_nil response["content-encoding"]
  ensure
    remove_request_stub(stub)
  end

  def test_decompress_response_noop_without_encoding
    stub = stub_request(:get, "https://api.example.com/data")
      .to_return(status: 200, body: '{"ok":true}')

    uri = URI("https://api.example.com/data")
    request = Net::HTTP::Get.new(uri)
    response = Braintrust::Internal::Http.with_redirects(uri, request)

    Braintrust::Internal::Http.decompress_response!(response)

    assert_equal '{"ok":true}', response.body
  ensure
    remove_request_stub(stub)
  end
end
