# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/experiments"

class Braintrust::Internal::ExperimentsTest < Minitest::Test
  def test_get_or_create_basic
    skip "Requires BRAINTRUST_API_KEY" unless ENV["BRAINTRUST_API_KEY"]

    VCR.use_cassette("experiments/get_or_create_basic") do
      Braintrust.init(blocking_login: true)
      state = Braintrust.current_state

      result = Braintrust::Internal::Experiments.get_or_create(
        "test-ruby-sdk-experiment-basic",
        "ruby-sdk-test",
        state: state
      )

      assert result[:experiment_id]
      assert result[:experiment_name]
      assert result[:project_id]
      assert_equal "ruby-sdk-test", result[:project_name]
    end
  end

  def test_get_or_create_with_tags_and_metadata
    skip "Requires BRAINTRUST_API_KEY" unless ENV["BRAINTRUST_API_KEY"]

    VCR.use_cassette("experiments/get_or_create_with_tags") do
      Braintrust.init(blocking_login: true)
      state = Braintrust.current_state

      result = Braintrust::Internal::Experiments.get_or_create(
        "test-ruby-sdk-experiment-tags",
        "ruby-sdk-test",
        state: state,
        tags: ["test", "ruby"],
        metadata: {version: "1.0", author: "claude"}
      )

      assert result[:experiment_id]
      assert result[:project_id]
    end
  end

  def test_get_or_create_with_update_flag
    skip "Requires BRAINTRUST_API_KEY" unless ENV["BRAINTRUST_API_KEY"]

    VCR.use_cassette("experiments/get_or_create_with_update") do
      Braintrust.init(blocking_login: true)
      state = Braintrust.current_state

      # First create with update: false (new experiment)
      result1 = Braintrust::Internal::Experiments.get_or_create(
        "test-experiment-update",
        "ruby-sdk-test",
        state: state,
        update: false
      )

      # Then with update: true (should allow reusing)
      result2 = Braintrust::Internal::Experiments.get_or_create(
        "test-experiment-update",
        "ruby-sdk-test",
        state: state,
        update: true
      )

      # Both should succeed and return experiment IDs
      assert result1[:experiment_id]
      assert result2[:experiment_id]
    end
  end

  def test_register_project_is_private
    # Test that register_project is private and cannot be called directly
    error = assert_raises(NoMethodError) do
      Braintrust::Internal::Experiments.register_project("test", nil)
    end

    assert_match(/private method|undefined method/, error.message)
  end

  def test_register_experiment_is_private
    # Test that register_experiment is private and cannot be called directly
    error = assert_raises(NoMethodError) do
      Braintrust::Internal::Experiments.register_experiment("test", "proj_id", nil)
    end

    assert_match(/private method|undefined method/, error.message)
  end
end
