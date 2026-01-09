# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
require "braintrust/contrib/openai/instrumentation/responses"

class Braintrust::Contrib::OpenAI::Instrumentation::ResponsesTest < Minitest::Test
  Responses = Braintrust::Contrib::OpenAI::Instrumentation::Responses

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
      include Braintrust::Contrib::OpenAI::Instrumentation::Responses
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
      include Braintrust::Contrib::OpenAI::Instrumentation::Responses
    end

    assert Responses.applied?(base)
  end
end

# E2E tests for Responses instrumentation
class Braintrust::Contrib::OpenAI::Instrumentation::ResponsesE2ETest < Minitest::Test
  include Braintrust::Contrib::OpenAI::IntegrationHelper

  def setup
    skip_unless_openai!
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)
  end

  # --- #create ---

  def test_create_creates_span_with_correct_attributes
    VCR.use_cassette("openai_responses_create_non_streaming") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.responses.create(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "What is 2+2?"
      )

      refute_nil response
      refute_nil response.output

      span = rig.drain_one

      assert_equal "openai.responses.create", span.name

      # Verify input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "What is 2+2?", input

      # Verify output
      assert span.attributes.key?("braintrust.output_json")

      # Verify metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/responses", metadata["endpoint"]
      assert_equal "gpt-4o-mini", metadata["model"]
      assert_equal "You are a helpful assistant.", metadata["instructions"]

      # Verify metrics include time_to_first_token
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_create_captures_metadata_field
    VCR.use_cassette("openai/responses_with_metadata") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.responses.create(
        model: "gpt-4o-mini",
        input: "Say hello",
        metadata: {user_id: "test-123", session: "abc"}
      )

      refute_nil response

      span = rig.drain_one
      span_metadata = JSON.parse(span.attributes["braintrust.metadata"])

      assert_equal({"user_id" => "test-123", "session" => "abc"}, span_metadata["metadata"])
    end
  end

  def test_create_captures_truncation_field
    VCR.use_cassette("openai/responses_with_truncation") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.responses.create(
        model: "gpt-4o-mini",
        input: "Say hello",
        truncation: "auto"
      )

      refute_nil response

      span = rig.drain_one
      metadata = JSON.parse(span.attributes["braintrust.metadata"])

      assert_equal "auto", metadata["truncation"]
    end
  end

  def test_create_captures_reasoning_field
    VCR.use_cassette("openai/responses_with_reasoning") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.responses.create(
        model: "o4-mini",
        input: "What is 2+2?",
        reasoning: {effort: "low"}
      )

      refute_nil response

      span = rig.drain_one
      metadata = JSON.parse(span.attributes["braintrust.metadata"])

      assert_equal({"effort" => "low"}, metadata["reasoning"])
    end
  end

  def test_create_captures_previous_response_id_field
    VCR.use_cassette("openai/responses_with_previous_response_id") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)

      # First request to get a response ID
      first_response = client.responses.create(
        model: "gpt-4o-mini",
        input: "Remember the number 42"
      )

      # Second request referencing the first
      response = client.responses.create(
        model: "gpt-4o-mini",
        input: "What number did I ask you to remember?",
        previous_response_id: first_response.id
      )

      refute_nil response

      spans = rig.drain
      assert_equal 2, spans.length

      # Check the second span has previous_response_id in metadata
      metadata = JSON.parse(spans[1].attributes["braintrust.metadata"])
      assert_equal first_response.id, metadata["previous_response_id"]
    end
  end

  def test_create_records_exception_on_error
    VCR.use_cassette("openai/responses_create_error") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      assert_raises do
        client.responses.create(
          model: "gpt-4o-mini",
          input: "test"
        )
      end

      span = rig.drain_one
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code
      assert span.events.any? { |e| e.name == "exception" }
    end
  end

  # --- #stream ---

  def test_stream_aggregates_events
    VCR.use_cassette("openai_responses_create_streaming") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.responses.stream(
        model: "gpt-4o-mini",
        input: "Count from 1 to 3"
      )

      event_count = 0
      stream.each { |event| event_count += 1 }

      assert event_count > 0

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "openai.responses.create", span.name

      # Span has input
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "Count from 1 to 3", input

      # Span has output
      assert span.attributes.key?("braintrust.output_json")

      # Verify metadata
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal true, metadata["stream"]

      # Verify metrics include time_to_first_token
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_stream_closes_span_on_partial_consumption
    VCR.use_cassette("openai_responses_stream_partial") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.responses.stream(
        model: "gpt-4o-mini",
        input: "Count from 1 to 10"
      )

      event_count = 0
      begin
        stream.each do |event|
          event_count += 1
          break if event_count >= 3
        end
      rescue StopIteration
      end

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "openai.responses.create", span.name
      assert span.attributes.key?("braintrust.input_json")
    end
  end

  def test_stream_records_exception_on_error
    VCR.use_cassette("openai/responses_stream_error") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      assert_raises do
        stream = client.responses.stream(
          model: "gpt-4o-mini",
          input: "test"
        )
        stream.each { |event| }
      end

      # No span created when stream fails before consumption
      spans = rig.drain
      assert_empty spans, "No span should be created when stream fails before consumption"
    end
  end
end
