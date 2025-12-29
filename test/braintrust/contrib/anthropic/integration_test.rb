# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"
require "braintrust/contrib/anthropic/integration"

class Braintrust::Contrib::Anthropic::IntegrationTest < Minitest::Test
  include Braintrust::Contrib::Anthropic::IntegrationHelper

  def setup
    load_anthropic_if_available
    @integration = Braintrust::Contrib::Anthropic::Integration
  end

  # --- .integration_name ---

  def test_integration_name
    assert_equal :anthropic, @integration.integration_name
  end

  # --- .gem_names ---

  def test_gem_names
    assert_equal ["anthropic"], @integration.gem_names
  end

  # --- .require_paths ---

  def test_require_paths
    assert_equal ["anthropic"], @integration.require_paths
  end

  # --- .minimum_version ---

  def test_minimum_version
    assert_equal "0.3.0", @integration.minimum_version
  end

  # --- .loaded? ---

  def test_loaded_returns_true_when_anthropic_client_defined
    skip "Anthropic gem not available" unless defined?(::Anthropic::Client)

    assert @integration.loaded?, "Should be loaded when ::Anthropic::Client is defined"
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
