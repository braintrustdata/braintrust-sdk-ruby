# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
require "braintrust/contrib/ruby_openai/instrumentation/moderations"

class Braintrust::Contrib::RubyOpenAI::Instrumentation::ModerationsTest < Minitest::Test
  Moderations = Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations

  # --- .included ---

  def test_included_prepends_instance_methods
    base = Class.new
    mock = Minitest::Mock.new
    mock.expect(:include?, false, [Moderations::InstanceMethods])
    mock.expect(:prepend, nil, [Moderations::InstanceMethods])

    base.define_singleton_method(:ancestors) { mock }
    base.define_singleton_method(:prepend) { |mod| mock.prepend(mod) }

    Moderations.included(base)

    mock.verify
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations
    end

    # Should not raise or double-prepend
    Moderations.included(base)

    # InstanceMethods should appear only once in ancestors
    count = base.ancestors.count { |a| a == Moderations::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new

    refute Moderations.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations
    end

    assert Moderations.applied?(base)
  end
end

# E2E tests for Moderations instrumentation
class Braintrust::Contrib::RubyOpenAI::Instrumentation::ModerationsE2ETest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  def setup
    skip_unless_ruby_openai!
    skip "Moderations API not available" unless OpenAI::Client.method_defined?(:moderations)
    @api_key = ENV["OPENAI_API_KEY"] || "test-api-key"
  end

  # --- #moderations ---

  def test_moderations_creates_span_with_correct_attributes
    VCR.use_cassette("alexrudall_ruby_openai/moderations") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      response = client.moderations(
        parameters: {
          input: "I want to harm someone"
        }
      )

      refute_nil response
      refute_nil response["results"]

      span = rig.drain_one

      assert_equal "openai.moderations.create", span.name

      # Verify input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "I want to harm someone", input

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output.is_a?(Array)
      assert output.first.key?("flagged")
      assert output.first.key?("categories")
      assert output.first.key?("category_scores")

      # Verify metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/moderations", metadata["endpoint"]
      assert metadata.key?("model")

      # Verify metrics include time_to_first_token
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_moderations_with_explicit_model
    VCR.use_cassette("alexrudall_ruby_openai/moderations_with_model") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      response = client.moderations(
        parameters: {
          input: "This is a test",
          model: "omni-moderation-latest"
        }
      )

      refute_nil response

      span = rig.drain_one
      metadata = JSON.parse(span.attributes["braintrust.metadata"])

      assert_equal "omni-moderation-latest", metadata["model"]
    end
  end

  def test_moderations_with_array_input
    VCR.use_cassette("alexrudall_ruby_openai/moderations_array") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      response = client.moderations(
        parameters: {
          input: ["First text", "Second text"]
        }
      )

      refute_nil response

      span = rig.drain_one

      # Verify input is array
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert input.is_a?(Array)
      assert_equal 2, input.length
      assert_equal "First text", input[0]
      assert_equal "Second text", input[1]

      # Verify output has results for both inputs
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 2, output.length
    end
  end

  def test_moderations_records_exception_on_error
    VCR.use_cassette("alexrudall_ruby_openai/moderations_error") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: "invalid_key")
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      assert_raises do
        client.moderations(
          parameters: {
            input: "test"
          }
        )
      end

      span = rig.drain_one
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code
      assert span.events.any? { |e| e.name == "exception" }
    end
  end
end
