# frozen_string_literal: true

require "test_helper"
require "braintrust/api/internal/projects"
require "braintrust/api/internal/experiments"

class Braintrust::API::Internal::ExperimentsTest < Minitest::Test
  PROJECT_NAME = "ruby-sdk-test"

  def test_create_returns_experiment_fields
    VCR.use_cassette("experiments/create_basic") do
      state = get_integration_test_state
      project = create_project(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      experiment = experiments.create(
        name: "experiments-test-basic",
        project_id: project["id"],
        ensure_new: false
      )

      assert experiment["id"], "should have an id"
      assert_equal "experiments-test-basic", experiment["name"]
      assert_equal project["id"], experiment["project_id"]
    ensure
      cleanup_experiment(experiments, experiment)
    end
  end

  def test_create_with_tags
    VCR.use_cassette("experiments/create_with_tags") do
      state = get_integration_test_state
      project = create_project(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      experiment = experiments.create(
        name: "experiments-test-tags",
        project_id: project["id"],
        ensure_new: false,
        tags: ["test", "sdk"]
      )

      assert experiment["id"], "should have an id"
    ensure
      cleanup_experiment(experiments, experiment)
    end
  end

  def test_create_with_ensure_new_false_is_idempotent
    VCR.use_cassette("experiments/create_idempotent") do
      state = get_integration_test_state
      project = create_project(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      first = experiments.create(
        name: "experiments-test-idempotent",
        project_id: project["id"],
        ensure_new: false
      )
      second = experiments.create(
        name: "experiments-test-idempotent",
        project_id: project["id"],
        ensure_new: false
      )

      assert_equal first["id"], second["id"]
    ensure
      cleanup_experiment(experiments, first)
    end
  end

  def test_create_raises_on_invalid_project
    VCR.use_cassette("experiments/create_invalid_project") do
      state = get_integration_test_state
      experiments = Braintrust::API::Internal::Experiments.new(state)

      assert_raises(Braintrust::Error) do
        experiments.create(name: "bad", project_id: "00000000-0000-0000-0000-000000000000")
      end
    end
  end

  def test_delete_returns_deleted_experiment
    VCR.use_cassette("experiments/delete") do
      state = get_integration_test_state
      project = create_project(state)
      experiments = Braintrust::API::Internal::Experiments.new(state)

      experiment = experiments.create(
        name: "experiments-test-delete",
        project_id: project["id"],
        ensure_new: false
      )

      deleted = experiments.delete(id: experiment["id"])
      assert_equal experiment["id"], deleted["id"]
    end
  end

  private

  def create_project(state)
    Braintrust::API::Internal::Projects.new(state).create(name: PROJECT_NAME)
  end

  def cleanup_experiment(experiments, experiment)
    experiments&.delete(id: experiment["id"]) if experiment
  rescue # best-effort cleanup
  end
end
