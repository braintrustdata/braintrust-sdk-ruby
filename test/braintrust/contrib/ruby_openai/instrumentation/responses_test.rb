# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
require "braintrust/contrib/ruby_openai/instrumentation/responses"

class Braintrust::Contrib::RubyOpenAI::Instrumentation::ResponsesTest < Minitest::Test
  Responses = Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses

  # --- .included ---

  def test_included_prepends_instance_methods
    base = Class.new
    mock = Minitest::Mock.new
    mock.expect(:include?, false, [Responses::InstanceMethods])
    mock.expect(:prepend, nil, [Responses::InstanceMethods])

    base.define_singleton_method(:ancestors) { mock }
    base.define_singleton_method(:prepend) { |mod| mock.prepend(mod) }

    Responses.included(base)

    mock.verify
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses
    end

    # Should not raise or double-prepend
    Responses.included(base)

    # InstanceMethods should appear only once in ancestors
    count = base.ancestors.count { |a| a == Responses::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new

    refute Responses.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses
    end

    assert Responses.applied?(base)
  end
end

# E2E tests for Responses instrumentation
class Braintrust::Contrib::RubyOpenAI::Instrumentation::ResponsesE2ETest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  def setup
    skip_unless_ruby_openai!
    @api_key = ENV["OPENAI_API_KEY"] || "test-api-key"
  end

  # --- #create ---

  def test_create_creates_span_with_correct_attributes
    VCR.use_cassette("alexrudall_ruby_openai/responses_non_streaming") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      skip "Responses API not available" unless client.respond_to?(:responses)

      response = client.responses.create(
        parameters: {
          model: "gpt-4o-mini",
          input: "What is 2+2? Reply with just the number."
        }
      )

      refute_nil response
      refute_nil response["output"]

      span = rig.drain_one

      assert_equal "openai.responses.create", span.name

      # Verify braintrust.input_json contains input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "What is 2+2? Reply with just the number.", input

      # Verify braintrust.output_json contains output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify braintrust.metadata contains request metadata
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/responses", metadata["endpoint"]
      assert_equal "gpt-4o-mini", metadata["model"]
      refute_nil metadata["id"]

      # Verify braintrust.metrics contains token usage
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_create_handles_streaming
    VCR.use_cassette("alexrudall_ruby_openai/responses_streaming") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      skip "Responses API not available" unless client.respond_to?(:responses)

      chunks = []
      client.responses.create(
        parameters: {
          model: "gpt-4o-mini",
          input: "Count from 1 to 3",
          stream: proc do |chunk, _event|
            chunks << chunk
          end
        }
      )

      refute_empty chunks

      span = rig.drain_one

      assert_equal "openai.responses.create", span.name

      # Verify braintrust.input_json contains input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "Count from 1 to 3", input

      # Verify braintrust.output_json contains aggregated output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify braintrust.metadata contains request metadata with stream flag
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/responses", metadata["endpoint"]
      assert_equal true, metadata["stream"]

      # Verify braintrust.metrics contains time_to_first_token
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_create_captures_metadata_parameter
    VCR.use_cassette("alexrudall_ruby_openai/responses_with_metadata") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      skip "Responses API not available" unless client.respond_to?(:responses)

      response = client.responses.create(
        parameters: {
          model: "gpt-4o-mini",
          input: "Say hello",
          metadata: {
            "test_key" => "test_value",
            "user_id" => "user_123"
          }
        }
      )

      refute_nil response

      span = rig.drain_one

      # Verify metadata parameter is captured in span metadata
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert metadata.key?("metadata"), "metadata parameter should be captured"
      assert_equal "test_value", metadata["metadata"]["test_key"]
      assert_equal "user_123", metadata["metadata"]["user_id"]
    end
  end

  def test_create_records_exception_on_error
    VCR.use_cassette("alexrudall_ruby_openai/responses_error") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: "invalid_key")
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      skip "Responses API not available" unless client.respond_to?(:responses)

      error = assert_raises do
        client.responses.create(
          parameters: {
            model: "gpt-4o-mini",
            input: "test"
          }
        )
      end

      refute_nil error

      span = rig.drain_one

      assert_equal "openai.responses.create", span.name
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code

      # Verify error message is captured
      refute_nil span.status.description
      assert span.status.description.length > 0

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }
    end
  end
end
