# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/setup"

class Braintrust::Contrib::SetupTest < Minitest::Test
  def setup
    # Reset the setup_complete flag before each test
    Braintrust::Contrib::Setup.instance_variable_set(:@setup_complete, nil)
  end

  def teardown
    # Reset after each test to not affect other tests
    Braintrust::Contrib::Setup.instance_variable_set(:@setup_complete, nil)
  end

  # --- run! idempotency ---

  def test_run_is_idempotent
    skip "Test not applicable when Rails is loaded" if defined?(::Rails::Railtie)

    call_count = 0

    ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: nil) do
      Braintrust::Contrib::Setup.stub(:setup_require_hook!, -> { call_count += 1 }) do
        Braintrust::Contrib::Setup.run!
        Braintrust::Contrib::Setup.run!
        Braintrust::Contrib::Setup.run!
      end
    end

    assert_equal 1, call_count, "run! should only execute once"
  end

  # --- BRAINTRUST_AUTO_INSTRUMENT env var ---

  def test_run_skips_hooks_when_auto_instrument_disabled
    hook_called = false

    ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "false") do
      Braintrust::Contrib::Setup.stub(:setup_require_hook!, -> { hook_called = true }) do
        Braintrust::Contrib::Setup.run!
      end
    end

    refute hook_called, "hooks should not be set up when auto_instrument is disabled"
  end

  def test_run_sets_up_hooks_when_auto_instrument_enabled
    skip "Test not applicable when Rails is loaded" if defined?(::Rails::Railtie)

    hook_called = false

    ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "true") do
      Braintrust::Contrib::Setup.stub(:setup_require_hook!, -> { hook_called = true }) do
        Braintrust::Contrib::Setup.run!
      end
    end

    assert hook_called, "hooks should be set up when auto_instrument is enabled"
  end

  def test_run_sets_up_hooks_by_default
    skip "Test not applicable when Rails is loaded" if defined?(::Rails::Railtie)

    hook_called = false

    # Ensure env var is not set
    ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: nil) do
      Braintrust::Contrib::Setup.stub(:setup_require_hook!, -> { hook_called = true }) do
        Braintrust::Contrib::Setup.run!
      end
    end

    assert hook_called, "hooks should be set up by default"
  end

  # --- rails_environment? ---

  def test_rails_environment_returns_false_when_rails_not_defined
    skip "Test not applicable when Rails is loaded" if defined?(::Rails::Railtie)

    refute Braintrust::Contrib::Setup.rails_environment?
  end

  def test_rails_environment_returns_false_when_rails_application_nil
    mock_rails = Module.new do
      def self.respond_to?(method)
        method == :application || super
      end

      def self.application
        nil
      end
    end

    Object.stub_const(:Rails, mock_rails) do
      refute Braintrust::Contrib::Setup.rails_environment?
    end
  end

  def test_rails_environment_returns_true_when_rails_railtie_defined
    with_mock_rails_railtie do
      assert Braintrust::Contrib::Setup.rails_environment?
    end
  end

  # --- setup_rails_hook! ---

  def test_setup_rails_hook_loads_railtie
    railtie_loaded = false

    Braintrust::Contrib::Setup.stub(:require_relative, ->(path) { railtie_loaded = true if path == "rails/railtie" }) do
      Braintrust::Contrib::Setup.setup_rails_hook!
    end

    assert railtie_loaded, "setup_rails_hook! should load rails/railtie"
  end

  # --- setup_require_hook! ---
  # These tests run in a fork to prevent the require hook from leaking into other tests

  def test_setup_require_hook_patches_kernel_require
    assert_in_fork do
      Braintrust::Contrib::Setup.setup_require_hook!

      # Check that require still works normally
      require "json" # Should work normally

      # If we got here without error, the hook is working
      puts "require_hook_test:passed"
    end
  end

  def test_setup_require_hook_instruments_matching_library
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "test_integration_lib", extension: ".rb") do |test_file|
        patch_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :test_lib,
          on_patch: -> { patch_called = true }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if patch_called
          puts "instrument_test:passed"
        else
          puts "instrument_test:failed - patch! was not called"
          exit 1
        end
      end
    end
  end

  def test_setup_require_hook_respects_only_filter
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "excluded_lib", extension: ".rb") do |test_file|
        patch_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :excluded_lib,
          on_patch: -> { patch_called = true }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        ENV["BRAINTRUST_INSTRUMENT_ONLY"] = "openai,anthropic"

        Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if patch_called
          puts "only_filter_test:failed - patch! should not be called for excluded lib"
          exit 1
        else
          puts "only_filter_test:passed"
        end
      end
    end
  end

  def test_setup_require_hook_respects_except_filter
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "excluded_lib", extension: ".rb") do |test_file|
        patch_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :excluded_lib,
          on_patch: -> { patch_called = true }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        ENV["BRAINTRUST_INSTRUMENT_EXCEPT"] = "excluded_lib"

        Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if patch_called
          puts "except_filter_test:failed - patch! should not be called for excluded lib"
          exit 1
        else
          puts "except_filter_test:passed"
        end
      end
    end
  end

  def test_setup_require_hook_skips_unavailable_integration
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "unavailable_lib", extension: ".rb") do |test_file|
        patch_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :unavailable_lib,
          available: false,
          on_patch: -> { patch_called = true }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if patch_called
          puts "unavailable_test:failed - patch! should not be called for unavailable integration"
          exit 1
        else
          puts "unavailable_test:passed"
        end
      end
    end
  end

  def test_setup_require_hook_skips_incompatible_integration
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "incompatible_lib", extension: ".rb") do |test_file|
        patch_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :incompatible_lib,
          compatible: false,
          on_patch: -> { patch_called = true }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if patch_called
          puts "incompatible_test:failed - patch! should not be called for incompatible integration"
          exit 1
        else
          puts "incompatible_test:passed"
        end
      end
    end
  end

  def test_setup_require_hook_has_reentrancy_guard
    assert_in_fork do
      with_tmp_file(data: "# reentrant lib\n", filename: "reentrant_lib", extension: ".rb") do |reentrant_file|
        with_tmp_file(data: "# nested lib\n", filename: "nested_lib", extension: ".rb") do |nested_file|
          require_calls_during_patch = []
          reentrant_lib_name = File.basename(reentrant_file.path, ".rb")
          nested_lib_name = File.basename(nested_file.path, ".rb")

          $LOAD_PATH.unshift(File.dirname(reentrant_file.path))
          $LOAD_PATH.unshift(File.dirname(nested_file.path))

          nested_name = nested_lib_name

          mock_integration = mock_integration_object(
            name: :reentrant_lib,
            on_patch: -> {
              require nested_name
              require_calls_during_patch << :patch_completed
            }
          )

          nested_integration = mock_integration_object(
            name: :nested_lib,
            on_patch: -> { require_calls_during_patch << :nested_patch_should_not_run }
          )

          mock_registry = mock_registry_for(
            reentrant_lib_name => [mock_integration],
            nested_lib_name => [nested_integration]
          )

          Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
            Braintrust::Contrib::Setup.setup_require_hook!
            require reentrant_lib_name
          end

          # The nested integration should NOT have been patched due to reentrancy guard
          if require_calls_during_patch == [:patch_completed]
            puts "reentrancy_test:passed"
          else
            puts "reentrancy_test:failed - got #{require_calls_during_patch.inspect}"
            exit 1
          end
        end
      end
    end
  end

  def test_setup_require_hook_logs_errors_without_crashing
    assert_in_fork do
      with_tmp_file(data: "# error lib\n", filename: "error_lib", extension: ".rb") do |test_file|
        error_logged = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        mock_integration = mock_integration_object(
          name: :error_lib,
          on_patch: -> { raise "Patch error!" }
        )

        mock_registry = mock_registry_for(test_lib_name => [mock_integration])

        with_stubs(
          [Braintrust::Contrib::Registry, :instance, mock_registry],
          [Braintrust::Log, :error, ->(_msg) { error_logged = true }]
        ) do
          Braintrust::Contrib::Setup.setup_require_hook!
          require test_lib_name
        end

        if error_logged
          puts "error_handling_test:passed"
        else
          puts "error_handling_test:failed - error was not logged"
          exit 1
        end
      end
    end
  end

  private

  # Helper to stub Rails with a Railtie class
  def with_mock_rails_railtie
    mock_rails = Module.new

    Object.stub_const(:Rails, mock_rails) do
      mock_rails.stub_const(:Railtie, Class.new) do
        yield
      end
    end
  end

  # Helper to create a mock integration object
  def mock_integration_object(name:, available: true, compatible: true, on_patch: nil)
    integration = Object.new
    integration.define_singleton_method(:integration_name) { name }
    integration.define_singleton_method(:available?) { available }
    integration.define_singleton_method(:compatible?) { compatible }
    integration.define_singleton_method(:patch!) { on_patch&.call }
    integration
  end

  # Helper to create a mock registry that maps lib names to integrations
  # @param mappings [Hash] lib_name => [integrations] mapping
  def mock_registry_for(mappings)
    registry = Object.new
    registry.define_singleton_method(:integrations_for_require_path) do |path|
      mappings.find { |lib_name, _| path.include?(lib_name) }&.last || []
    end
    registry
  end
end
