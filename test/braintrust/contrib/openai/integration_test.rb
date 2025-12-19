# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::OpenAI::IntegrationTest < Minitest::Test
  def setup
    @integration = Braintrust::Contrib::OpenAI::Integration
  end

  # --- .integration_name ---

  def test_integration_name
    assert_equal :openai, @integration.integration_name
  end

  # --- .gem_names ---

  def test_gem_names
    assert_equal ["openai"], @integration.gem_names
  end

  # --- .require_paths ---

  def test_require_paths
    assert_equal ["openai"], @integration.require_paths
  end

  # --- .minimum_version ---

  def test_minimum_version
    assert_equal "0.1.0", @integration.minimum_version
  end

  # --- .loaded? ---

  def test_loaded_returns_true_when_openai_internal_defined
    skip "OpenAI gem not loaded" unless defined?(::OpenAI::Internal)

    assert @integration.loaded?, "Should be loaded when ::OpenAI::Internal is defined"
  end

  def test_loaded_returns_false_when_openai_internal_not_defined
    skip "OpenAI gem is loaded" if defined?(::OpenAI::Internal)

    refute @integration.loaded?, "Should not be loaded when ::OpenAI::Internal is not defined"
  end

  # --- .patchers ---

  def test_patchers_returns_array_of_patcher_classes
    patcher_classes = @integration.patchers

    assert_instance_of Array, patcher_classes
    assert patcher_classes.length > 0, "patchers should return at least one patcher"
    patcher_classes.each do |patcher_class|
      assert patcher_class.is_a?(Class), "each patcher should be a Class"
      assert patcher_class < Braintrust::Contrib::Patcher, "each patcher should inherit from Patcher"
    end
  end
end
