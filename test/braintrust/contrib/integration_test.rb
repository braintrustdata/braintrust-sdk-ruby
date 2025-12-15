# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::IntegrationTest < Minitest::Test
  def setup
    # Use anonymous subclass to isolate test state
    registry_class = Class.new(Braintrust::Contrib::Registry)
    @registry = registry_class.instance
  end

  # Create a mock patcher class for testing
  def create_mock_patcher(should_fail: false, applicable: true)
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      class << self
        attr_accessor :patch_called, :should_fail, :is_applicable
      end

      def self.applicable?
        @is_applicable
      end

      def self.perform_patch(**options)
        @patch_called = true
        raise "Patch failed" if @should_fail
      end
    end

    patcher.patch_called = false
    patcher.should_fail = should_fail
    patcher.is_applicable = applicable
    patcher
  end

  # Create a full integration class for testing
  def create_test_integration(
    name:,
    gem_names:,
    require_paths: nil,
    patcher: nil,
    min_version: nil,
    max_version: nil
  )
    patcher_class = patcher || create_mock_patcher

    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_integration_name, :_gem_names, :_require_paths,
          :_patcher, :_min_version, :_max_version
      end

      def self.integration_name
        _integration_name
      end

      def self.gem_names
        _gem_names
      end

      def self.require_paths
        _require_paths || _gem_names
      end

      def self.minimum_version
        _min_version
      end

      def self.maximum_version
        _max_version
      end

      def self.patcher
        _patcher
      end
    end

    integration._integration_name = name
    integration._gem_names = gem_names
    integration._require_paths = require_paths
    integration._patcher = patcher_class
    integration._min_version = min_version
    integration._max_version = max_version
    integration
  end

  def test_integration_name_raises_not_implemented
    integration = Class.new { include Braintrust::Contrib::Integration }

    assert_raises(NotImplementedError) do
      integration.integration_name
    end
  end

  def test_gem_names_raises_not_implemented
    integration = Class.new { include Braintrust::Contrib::Integration }

    assert_raises(NotImplementedError) do
      integration.gem_names
    end
  end

  def test_patcher_raises_not_implemented
    integration = Class.new { include Braintrust::Contrib::Integration }

    assert_raises(NotImplementedError) do
      integration.patcher
    end
  end

  def test_patchers_defaults_to_wrapping_patcher
    patcher = create_mock_patcher
    integration = create_test_integration(
      name: :test,
      gem_names: ["minitest"],
      patcher: patcher
    )

    assert_equal [patcher], integration.patchers
  end

  def test_require_paths_defaults_to_gem_names
    integration = create_test_integration(
      name: :test,
      gem_names: ["test-gem", "other-gem"]
    )

    assert_equal ["test-gem", "other-gem"], integration.require_paths
  end

  def test_require_paths_can_be_overridden
    integration = create_test_integration(
      name: :test,
      gem_names: ["test-gem"],
      require_paths: ["custom_path", "another_path"]
    )

    assert_equal ["custom_path", "another_path"], integration.require_paths
  end

  def test_minimum_version_defaults_to_nil
    integration = create_test_integration(
      name: :test,
      gem_names: ["test-gem"]
    )

    assert_nil integration.minimum_version
  end

  def test_maximum_version_defaults_to_nil
    integration = create_test_integration(
      name: :test,
      gem_names: ["test-gem"]
    )

    assert_nil integration.maximum_version
  end

  def test_available_checks_gem_loaded_specs
    # Use a gem that is actually loaded (minitest)
    integration = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"]
    )

    assert integration.available?
  end

  def test_available_returns_false_for_unloaded_gem
    integration = create_test_integration(
      name: :test,
      gem_names: ["nonexistent-gem-xyz-123"]
    )

    refute integration.available?
  end

  def test_available_with_multiple_gems_any_loaded
    # minitest is loaded, fake-gem is not
    integration = create_test_integration(
      name: :test,
      gem_names: ["fake-gem-xyz", "minitest"]
    )

    assert integration.available?
  end

  def test_compatible_returns_false_when_not_available
    integration = create_test_integration(
      name: :test,
      gem_names: ["nonexistent-gem-xyz-123"]
    )

    refute integration.compatible?
  end

  def test_compatible_returns_true_when_no_version_constraints
    integration = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"]
    )

    assert integration.compatible?
  end

  def test_compatible_checks_minimum_version
    # Get the current minitest version
    Gem.loaded_specs["minitest"].version

    # Test with a minimum version below current
    integration_ok = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"],
      min_version: "1.0.0"
    )
    assert integration_ok.compatible?

    # Test with a minimum version above current
    integration_too_new = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"],
      min_version: "999.0.0"
    )
    refute integration_too_new.compatible?
  end

  def test_compatible_checks_maximum_version
    # Test with a maximum version above current
    integration_ok = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"],
      max_version: "999.0.0"
    )
    assert integration_ok.compatible?

    # Test with a maximum version below current
    integration_too_old = create_test_integration(
      name: :minitest_test,
      gem_names: ["minitest"],
      max_version: "0.0.1"
    )
    refute integration_too_old.compatible?
  end

  def test_patch_delegates_to_patcher
    patcher = create_mock_patcher
    integration = create_test_integration(
      name: :test,
      gem_names: ["minitest"],
      patcher: patcher
    )

    result = integration.patch!

    assert result
    assert patcher.patch_called
  end

  def test_patch_returns_false_when_not_available
    patcher = create_mock_patcher
    integration = create_test_integration(
      name: :test,
      gem_names: ["nonexistent-gem-xyz-123"],
      patcher: patcher
    )

    result = integration.patch!

    refute result
    refute patcher.patch_called
  end

  def test_patch_returns_false_when_not_compatible
    patcher = create_mock_patcher
    integration = create_test_integration(
      name: :test,
      gem_names: ["minitest"],
      min_version: "999.0.0", # Too high
      patcher: patcher
    )

    result = integration.patch!

    refute result
    refute patcher.patch_called
  end

  def test_patch_passes_tracer_provider
    received_options = nil
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      class << self
        attr_accessor :is_applicable
      end

      def self.applicable?
        @is_applicable
      end

      define_singleton_method(:perform_patch) do |**options|
        received_options = options
      end
    end
    patcher.is_applicable = true

    integration = create_test_integration(
      name: :test,
      gem_names: ["minitest"],
      patcher: patcher
    )

    tracer_provider = Object.new
    integration.patch!(tracer_provider: tracer_provider)

    assert_equal tracer_provider, received_options[:tracer_provider]
  end

  def test_register_adds_to_registry
    integration = create_test_integration(
      name: :test_integration,
      gem_names: ["test-gem"]
    )

    # Mock Registry.instance to verify register! calls it
    mock_registry = Minitest::Mock.new
    mock_registry.expect(:register, nil, [integration])

    Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
      integration.register!
    end

    mock_registry.verify
  end

  def test_patchers_with_multiple_patchers
    patcher1 = create_mock_patcher
    patcher2 = create_mock_patcher

    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_patchers
      end

      def self.integration_name
        :test
      end

      def self.gem_names
        ["minitest"]
      end

      def self.patchers
        _patchers
      end
    end

    integration._patchers = [patcher1, patcher2]

    assert_equal [patcher1, patcher2], integration.patchers
  end

  def test_patch_tries_all_applicable_patchers
    # First patcher is not applicable
    patcher1 = create_mock_patcher(applicable: false)

    # Second and third patchers are applicable - both should be tried
    patcher2 = create_mock_patcher(applicable: true)
    patcher3 = create_mock_patcher(applicable: true)

    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_patchers
      end

      def self.integration_name
        :test
      end

      def self.gem_names
        ["minitest"]
      end

      def self.patchers
        _patchers
      end
    end

    integration._patchers = [patcher1, patcher2, patcher3]

    result = integration.patch!

    assert result
    refute patcher1.patch_called # Not applicable
    assert patcher2.patch_called # Applied
    assert patcher3.patch_called # Also applied (doesn't stop after patcher2)
  end

  def test_patch_skips_non_applicable_patchers
    # Create patcher that is not applicable
    non_applicable_patcher = create_mock_patcher(applicable: false)

    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_patcher
      end

      def self.integration_name
        :test
      end

      def self.gem_names
        ["minitest"]
      end

      def self.patchers
        [_patcher]
      end
    end

    integration._patcher = non_applicable_patcher

    result = integration.patch!

    refute result
    refute non_applicable_patcher.patch_called
  end

  def test_patch_logs_when_no_applicable_patcher
    non_applicable_patcher = create_mock_patcher(applicable: false)

    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_patcher
      end

      def self.integration_name
        :test
      end

      def self.gem_names
        ["minitest"]
      end

      def self.patchers
        [_patcher]
      end
    end

    integration._patcher = non_applicable_patcher

    # Capture log output
    captured_logs = []
    original_logger = Braintrust::Log.logger
    test_logger = Logger.new(StringIO.new)
    test_logger.level = Logger::DEBUG
    test_logger.formatter = ->(_severity, _time, _progname, msg) {
      captured_logs << msg
      ""
    }
    Braintrust::Log.logger = test_logger

    begin
      integration.patch!
      # Check that the "no applicable patcher" message was logged
      assert captured_logs.any? { |msg| msg.include?("No applicable patcher found") }
    ensure
      Braintrust::Log.logger = original_logger
    end
  end
end
