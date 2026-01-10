# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

class Braintrust::Contrib::RubyLLM::IntegrationTest < Minitest::Test
  include Braintrust::Contrib::RubyLLM::IntegrationHelper

  def setup
    load_ruby_llm_if_available
    @integration = Braintrust::Contrib::RubyLLM::Integration
  end

  # --- .integration_name ---

  def test_integration_name
    assert_equal :ruby_llm, @integration.integration_name
  end

  # --- .gem_names ---

  def test_gem_names
    assert_equal ["ruby_llm"], @integration.gem_names
  end

  # --- .require_paths ---

  def test_require_paths
    assert_equal ["ruby_llm"], @integration.require_paths
  end

  # --- .minimum_version ---

  def test_minimum_version
    assert_equal "1.8.0", @integration.minimum_version
  end

  # --- .loaded? ---

  def test_loaded_returns_true_when_ruby_llm_chat_defined
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    assert @integration.loaded?, "Should be loaded when ::RubyLLM::Chat is defined"
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
