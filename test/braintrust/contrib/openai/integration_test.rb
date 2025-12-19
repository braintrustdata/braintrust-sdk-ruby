# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::OpenAI::IntegrationTest < Minitest::Test
  def setup
    @integration = Braintrust::Contrib::OpenAI::Integration
  end

  def test_integration_name
    assert_equal :openai, @integration.integration_name
  end

  def test_gem_names
    assert_equal ["openai"], @integration.gem_names
  end

  def test_require_paths
    assert_equal ["openai"], @integration.require_paths
  end

  def test_minimum_version
    assert_equal "0.1.0", @integration.minimum_version
  end

  def test_maximum_version
    assert_nil @integration.maximum_version
  end

  def test_available_when_openai_gem_loaded
    # Mock Gem.loaded_specs to include "openai" gem
    original_specs = Gem.loaded_specs.dup
    begin
      Gem.loaded_specs["openai"] = Gem::Specification.new("openai", "1.0.0")
      assert @integration.available?, "Should be available when openai gem is in loaded_specs"
    ensure
      Gem.loaded_specs.replace(original_specs)
    end
  end

  def test_available_with_loaded_features
    # Skip this test if openai gem is actually loaded (we can't properly mock it)
    skip "OpenAI gem is loaded, can't test $LOADED_FEATURES path in isolation" if Gem.loaded_specs.key?("openai")

    # Mock $LOADED_FEATURES to include openai gem path
    # This simulates the gem being loaded via require 'openai'
    original_features = $LOADED_FEATURES.dup
    begin
      $LOADED_FEATURES.replace(["/path/to/gems/openai-1.0.0/lib/openai.rb"])

      assert @integration.available?, "Should be available when openai.rb is in $LOADED_FEATURES with openai- in path"
    ensure
      $LOADED_FEATURES.replace(original_features)
    end
  end

  def test_not_available_when_ruby_openai_gem_loaded
    # The ruby-openai gem also uses 'openai' in require path but has different gem name
    # It should NOT match because:
    # 1. Gem.loaded_specs won't have "openai" key (it has "ruby-openai")
    # 2. $LOADED_FEATURES will have /ruby-openai-/ in path, not /openai-/
    original_specs = Gem.loaded_specs.dup
    original_features = $LOADED_FEATURES.dup
    begin
      # Clear any openai gem
      Gem.loaded_specs.delete("openai")
      # Add ruby-openai gem
      Gem.loaded_specs["ruby-openai"] = Gem::Specification.new("ruby-openai", "1.0.0")
      # Add to $LOADED_FEATURES with ruby-openai path
      $LOADED_FEATURES.replace(["/path/to/gems/ruby-openai-1.0.0/lib/openai.rb"])

      refute @integration.available?, "Should NOT be available when only ruby-openai gem is loaded"
    ensure
      Gem.loaded_specs.replace(original_specs)
      $LOADED_FEATURES.replace(original_features)
    end
  end

  def test_not_available_when_no_gem_loaded
    # Mock Gem.loaded_specs and $LOADED_FEATURES to have no openai
    original_specs = Gem.loaded_specs.dup
    original_features = $LOADED_FEATURES.dup
    begin
      Gem.loaded_specs.delete("openai")
      $LOADED_FEATURES.replace(["/some/other/gem.rb"])

      refute @integration.available?, "Should not be available when openai gem is not loaded"
    ensure
      Gem.loaded_specs.replace(original_specs)
      $LOADED_FEATURES.replace(original_features)
    end
  end

  def test_compatible_when_available
    skip "OpenAI gem not available" unless defined?(::OpenAI)
    skip "ruby-openai gem loaded instead" if Gem.loaded_specs["ruby-openai"]

    # If openai gem is actually loaded in test environment
    if @integration.available?
      assert @integration.compatible?, "Should be compatible when available and version is acceptable"
    end
  end

  def test_patchers_lazy_loads
    # The patchers should not be loaded until we call patchers method
    # We can't easily test this without unloading the constants, so we'll just
    # verify that patchers returns an array of classes
    patcher_classes = @integration.patchers
    assert patcher_classes.is_a?(Array), "patchers should return an Array"
    assert patcher_classes.length > 0, "patchers should return at least one patcher"
    patcher_classes.each do |patcher_class|
      assert patcher_class.is_a?(Class), "each patcher should be a Class"
      assert patcher_class < Braintrust::Contrib::Patcher, "each patcher should inherit from Patcher"
    end
  end

  def test_patch_returns_false_when_not_available
    with_stubbed_singleton_method(@integration, :available?, -> { false }) do
      result = @integration.patch!(tracer_provider: nil)
      refute result, "patch! should return false when not available"
    end
  end

  def test_register_adds_to_registry
    # Clear registry for clean test
    registry = Braintrust::Contrib::Registry.instance
    registry.clear!

    # Register the integration
    @integration.register!

    # Verify it's in the registry
    assert_equal @integration, registry[:openai]
    assert registry.all.include?(@integration)
  ensure
    registry.clear!
    # Re-register for other tests
    @integration.register!
  end
end
