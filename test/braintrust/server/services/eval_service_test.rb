# frozen_string_literal: true

require "test_helper"
require "json"

# Unit tests for Services::Eval — runs without any framework (no appraisal needed).
module Braintrust
  module Server
    module Services
      class EvalTest < Minitest::Test
        def setup
          skip_unless_server!
          @evaluators = {}
          @rig = setup_otel_test_rig
        end

        def service
          Eval.new(@evaluators)
        end

        # --- validate ---

        def test_validate_returns_error_for_missing_name
          result = service.validate({})
          assert_equal 400, result[:status]
          assert_match(/name/, result[:error])
        end

        def test_validate_returns_error_for_unknown_evaluator
          result = service.validate({"name" => "nonexistent", "data" => {"data" => []}})
          assert_equal 404, result[:status]
          assert_match(/not found/i, result[:error])
        end

        def test_validate_returns_error_for_missing_data
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({"name" => "test-eval"})
          assert_equal 400, result[:status]
          assert_match(/data/, result[:error])
        end

        def test_validate_returns_error_for_multiple_data_sources
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "test-eval",
            "data" => {"data" => [{"input" => "x"}], "dataset_name" => "ds"}
          })
          assert_equal 400, result[:status]
        end

        def test_validate_returns_valid_hash_on_success
          @evaluators["my-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "my-eval",
            "data" => {"data" => [{"input" => "hello", "expected" => "hello"}]},
            "experiment_name" => "exp-1",
            "project_id" => "proj-1"
          })

          refute result.key?(:error)
          assert_equal "my-eval", result[:name]
          assert_equal @evaluators["my-eval"], result[:evaluator]
          assert_equal [{input: "hello", expected: "hello"}], result[:cases]
          assert_equal "exp-1", result[:experiment_name]
          assert_equal "proj-1", result[:project_id]
        end

        def test_validate_accepts_dataset_id
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "test-eval",
            "data" => {"dataset_id" => "ds-123"}
          })

          refute result.key?(:error)
          assert_nil result[:cases]
          assert_instance_of Braintrust::Dataset::ID, result[:dataset]
        end

        def test_validate_accepts_dataset_name
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "test-eval",
            "data" => {"dataset_name" => "my-dataset", "project_name" => "my-project"}
          })

          refute result.key?(:error)
          assert_nil result[:cases]
          assert_equal({name: "my-dataset", project: "my-project"}, result[:dataset])
        end

        # --- stream ---

        def test_stream_emits_progress_and_done_events
          @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase }, scorers: [noop_scorer])
          s = service
          validated = s.validate({
            "name" => "upcase-eval",
            "data" => {"data" => [{"input" => "hello"}, {"input" => "world"}]},
            "experiment_name" => "exp"
          })

          events = collect_streamed_events(s, validated)

          progress = events.select { |e| e[:event] == "progress" }
          assert_equal 4, progress.length # 2 per case: json_delta + done
          assert_equal "done", events.last[:event]
        end

        def test_stream_emits_summary_with_scores
          scorer = Braintrust::Eval.scorer("exact") { |_i, e, o| (o == e) ? 1.0 : 0.0 }
          @evaluators["scored-eval"] = test_evaluator(
            task: ->(input) { input.to_s.upcase },
            scorers: [scorer]
          )
          s = service
          validated = s.validate({
            "name" => "scored-eval",
            "data" => {"data" => [{"input" => "hello", "expected" => "HELLO"}]},
            "experiment_name" => "my-exp"
          })

          events = collect_streamed_events(s, validated)
          summary = events.find { |e| e[:event] == "summary" }
          data = JSON.parse(summary[:data])

          assert data.key?("scores")
          assert_equal "my-exp", data["experiment_name"]
        end

        def test_stream_emits_error_progress_on_task_failure
          @evaluators["failing-eval"] = test_evaluator(task: ->(_input) { raise "boom" }, scorers: [noop_scorer])
          s = service
          validated = s.validate({
            "name" => "failing-eval",
            "data" => {"data" => [{"input" => "x"}]},
            "experiment_name" => "exp"
          })

          events = collect_streamed_events(s, validated)
          progress = events.find { |e| e[:event] == "progress" }
          data = JSON.parse(progress[:data])

          assert_equal "error", data["event"]
          assert_match(/boom/, data["data"])
          assert_equal "done", events.last[:event]
        end

        def test_stream_does_not_pass_state_when_auth_is_not_hash
          received_opts = nil
          spy = test_evaluator(
            task: ->(input) { input },
            scorers: [Braintrust::Eval.scorer("s") { |_i, _e, _o| 1.0 }]
          )
          spy.define_singleton_method(:run) do |cases, **opts|
            received_opts = opts
            Braintrust::Eval::Result.new(
              experiment_id: nil, experiment_name: nil,
              project_id: nil, project_name: nil,
              permalink: nil, scores: {}, errors: [], duration: 0.01
            )
          end

          @evaluators["spy-eval"] = spy
          s = service
          validated = s.validate({
            "name" => "spy-eval",
            "data" => {"data" => [{"input" => "x"}]},
            "experiment_name" => "exp"
          })

          collect_streamed_events(s, validated, auth: true) # NoAuth returns true

          assert_nil received_opts[:state]
        end

        # --- validate: parameters ---

        def test_validate_extracts_parameters_from_body
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "test-eval",
            "data" => {"data" => [{"input" => "x"}]},
            "parameters" => {"model" => "gpt-4", "temperature" => 0.7}
          })

          refute result.key?(:error)
          assert_equal({"model" => "gpt-4", "temperature" => 0.7}, result[:parameters])
        end

        def test_validate_merges_parameters_with_evaluator_defaults
          @evaluators["test-eval"] = test_evaluator(
            task: ->(input) { input },
            parameters: {
              "model" => {type: "string", default: "gpt-3.5"},
              "temperature" => {type: "number", default: 0.5}
            }
          )
          result = service.validate({
            "name" => "test-eval",
            "data" => {"data" => [{"input" => "x"}]},
            "parameters" => {"model" => "gpt-4"}
          })

          refute result.key?(:error)
          assert_equal "gpt-4", result[:parameters]["model"]
          assert_equal 0.5, result[:parameters]["temperature"]
        end

        def test_validate_returns_empty_parameters_when_none_provided
          @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })
          result = service.validate({
            "name" => "test-eval",
            "data" => {"data" => [{"input" => "x"}]}
          })

          refute result.key?(:error)
          assert_equal({}, result[:parameters])
        end

        def test_stream_passes_parameters_to_evaluator_run
          received_opts = nil
          spy = test_evaluator(task: ->(input) { input })
          spy.define_singleton_method(:run) do |cases, **opts|
            received_opts = opts
            Braintrust::Eval::Result.new(
              experiment_id: nil, experiment_name: nil,
              project_id: nil, project_name: nil,
              permalink: nil, scores: {}, errors: [], duration: 0.01
            )
          end

          @evaluators["spy-eval"] = spy
          s = service
          validated = s.validate({
            "name" => "spy-eval",
            "data" => {"data" => [{"input" => "x"}]},
            "parameters" => {"model" => "gpt-4"}
          })

          collect_streamed_events(s, validated, auth: true)

          assert_equal({"model" => "gpt-4"}, received_opts[:parameters])
        end

        def test_stream_does_not_pass_empty_parameters
          received_opts = nil
          spy = test_evaluator(task: ->(input) { input })
          spy.define_singleton_method(:run) do |cases, **opts|
            received_opts = opts
            Braintrust::Eval::Result.new(
              experiment_id: nil, experiment_name: nil,
              project_id: nil, project_name: nil,
              permalink: nil, scores: {}, errors: [], duration: 0.01
            )
          end

          @evaluators["spy-eval"] = spy
          s = service
          validated = s.validate({
            "name" => "spy-eval",
            "data" => {"data" => [{"input" => "x"}]}
          })

          collect_streamed_events(s, validated, auth: true)

          refute received_opts.key?(:parameters)
        end

        # --- build_state ---

        def test_build_state_returns_nil_for_non_hash_auth
          assert_nil service.build_state(nil)
          assert_nil service.build_state(true)
          assert_nil service.build_state("string")
        end

        def test_build_state_caches_by_auth_key
          s = service
          auth = {
            "api_key" => "key-1",
            "org_id" => "org-1",
            "org_name" => "org",
            "app_url" => "https://app.example.com",
            "api_url" => "https://api.example.com"
          }

          state1 = s.build_state(auth)
          state2 = s.build_state(auth)

          assert_same state1, state2
        end

        def test_build_state_returns_different_state_for_different_keys
          s = service
          auth_a = {"api_key" => "key-a", "org_id" => "org-a", "org_name" => "org-a",
                    "app_url" => "https://a.example.com", "api_url" => "https://a.example.com"}
          auth_b = {"api_key" => "key-b", "org_id" => "org-b", "org_name" => "org-b",
                    "app_url" => "https://b.example.com", "api_url" => "https://b.example.com"}

          state_a = s.build_state(auth_a)
          state_b = s.build_state(auth_b)

          refute_same state_a, state_b
        end

        def test_build_state_evicts_oldest_when_cache_full
          s = service

          65.times do |i|
            auth = {
              "api_key" => "key-#{i}",
              "org_id" => "org-#{i}",
              "org_name" => "org-#{i}",
              "app_url" => "https://app.example.com",
              "api_url" => "https://api.example.com"
            }
            s.build_state(auth)
          end

          cache = s.instance_variable_get(:@state_cache)
          assert_equal 64, cache.size
          refute cache.key?(["key-0", "https://app.example.com", "org-0"]),
            "Oldest entry should have been evicted"
        end

        private

        def test_evaluator(**kwargs)
          Test::Support::EvalHelper::TestEvaluator.new(tracer_provider: @rig.tracer_provider, **kwargs)
        end

        def noop_scorer
          Braintrust::Scorer.new("noop") { 1.0 }
        end

        def collect_streamed_events(svc, validated, auth: nil)
          chunks = []
          sse = Braintrust::Server::SSEWriter.new { |chunk| chunks << chunk }
          svc.stream(validated, auth: auth, sse: sse)
          parse_sse_events(chunks.join)
        end
      end
    end
  end
end
