# frozen_string_literal: true

require "test_helper"
require "braintrust/api/internal/btql"
require "braintrust/api/internal/projects"
require "braintrust/api/internal/experiments"

class Braintrust::API::Internal::BTQLIntegrationTest < Minitest::Test
  PROJECT_NAME = "ruby-sdk-test"

  def test_trace_spans_queries_experiment
    VCR.use_cassette("btql/trace_spans") do
      state = get_integration_test_state(enable_tracing: false)
      projects = Braintrust::API::Internal::Projects.new(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      project = projects.create(name: PROJECT_NAME)
      experiment = experiments.create(
        name: "btql-trace-test",
        project_id: project["id"],
        ensure_new: false
      )

      # Generate OTel spans using a test rig (synchronous, no background threads)
      rig = setup_otel_test_rig
      tracer = rig.tracer("btql-integration-test")
      root_span_id = nil

      tracer.in_span("eval") do |eval_span|
        eval_span.set_attribute("braintrust.parent", "experiment_id:#{experiment["id"]}")
        root_span_id = eval_span.context.hex_trace_id

        tracer.in_span("task") do |task_span|
          task_span.set_attribute("braintrust.span_attributes", '{"type":"task"}')
          task_span.set_attribute("braintrust.input_json", '{"text":"hello"}')
          task_span.set_attribute("braintrust.output_json", '{"result":"5"}')
        end
      end
      rig.tracer_provider.force_flush

      # Query back via BTQL
      btql = Braintrust::API::Internal::BTQL.new(state)
      result = btql.trace_spans(
        object_type: "experiment",
        object_id: experiment["id"],
        root_span_id: root_span_id
      )

      refute_empty result, "BTQL should return spans for the trace"

      result.each do |span|
        assert span.key?("span_id"), "span should have span_id"
        assert span.key?("root_span_id"), "span should have root_span_id"
        assert span.key?("span_attributes"), "span should have span_attributes"
      end

      # Verify score spans are excluded by the query filter
      types = result.map { |s| s.dig("span_attributes", "type") }
      refute_includes types, "score"
    ensure
      cleanup_experiment(experiments, experiment)
    end
  end

  def test_trace_spans_returns_empty_for_nonexistent_trace
    VCR.use_cassette("btql/trace_spans_empty") do
      state = get_integration_test_state(enable_tracing: false)
      projects = Braintrust::API::Internal::Projects.new(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      project = projects.create(name: PROJECT_NAME)
      experiment = experiments.create(
        name: "btql-empty-test",
        project_id: project["id"],
        ensure_new: false
      )

      btql = Braintrust::API::Internal::BTQL.new(state)

      Braintrust::API::Internal::BTQL.stub_const(:FRESHNESS_BASE_DELAY, 0.001) do
        Braintrust::API::Internal::BTQL.stub_const(:MAX_FRESHNESS_DELAY, 0.001) do
          result = btql.trace_spans(
            object_type: "experiment",
            object_id: experiment["id"],
            root_span_id: "0000000000000000ffffffffffffffff"
          )

          assert_equal [], result
        end
      end
    ensure
      cleanup_experiment(experiments, experiment)
    end
  end

  private

  def cleanup_experiment(experiments, experiment)
    experiments&.delete(id: experiment["id"]) if experiment
  rescue # best-effort cleanup
  end
end
