# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/setup"

class Braintrust::Contrib::SetupTest < Minitest::Test
  # --- run! ---

  def test_run_skips_when_auto_instrument_disabled
    assert_in_fork do
      hook_installed = false

      ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "false") do
        with_stubs(
          [Braintrust::Contrib::Setup, :install_watcher_hook!, -> { hook_installed = true }],
          [Braintrust::Contrib::Setup, :install_require_hook!, -> { hook_installed = true }],
          [Braintrust::Contrib::Setup, :install_railtie!, -> { hook_installed = true }]
        ) do
          Braintrust::Contrib::Setup.run!
        end
      end

      refute hook_installed, "hooks should not be installed when auto_instrument is disabled"
    end
  end

  def test_run_installs_railtie_when_rails_defined
    skip "Test not applicable when Rails is already loaded" if defined?(::Rails::Railtie)

    assert_in_fork do
      railtie_installed = false

      with_mock_rails_railtie do
        Braintrust::Contrib::Setup.stub(:install_railtie!, -> { railtie_installed = true }) do
          ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "true") do
            Braintrust::Contrib::Setup.run!
          end
        end
      end

      assert railtie_installed, "should install railtie when Rails::Railtie is defined"
    end
  end

  def test_run_installs_require_hook_when_zeitwerk_defined
    skip "Test not applicable when Rails or Zeitwerk is loaded" if defined?(::Rails::Railtie) || defined?(::Zeitwerk)

    assert_in_fork do
      require_hook_installed = false

      with_mock_zeitwerk do
        Braintrust::Contrib::Setup.stub(:install_require_hook!, -> { require_hook_installed = true }) do
          ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "true") do
            Braintrust::Contrib::Setup.run!
          end
        end
      end

      assert require_hook_installed, "should install require hook when Zeitwerk is defined"
    end
  end

  def test_run_installs_watcher_hook_when_neither_rails_nor_zeitwerk
    skip "Test not applicable when Rails or Zeitwerk is loaded" if defined?(::Rails::Railtie) || defined?(::Zeitwerk)

    assert_in_fork do
      watcher_installed = false

      Braintrust::Contrib::Setup.stub(:install_watcher_hook!, -> { watcher_installed = true }) do
        ClimateControl.modify(BRAINTRUST_AUTO_INSTRUMENT: "true") do
          Braintrust::Contrib::Setup.run!
        end
      end

      assert watcher_installed, "should install watcher hook when neither Rails nor Zeitwerk is defined"
    end
  end

  # --- on_require ---

  def test_on_require_patches_matching_integration
    assert_in_fork do
      patch_called = false

      mock_integration = mock_integration_object(
        name: :test_lib,
        on_patch: -> { patch_called = true }
      )

      mock_registry = mock_registry_for("test_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
      Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

      Braintrust::Contrib::Setup.on_require("test_lib")

      assert patch_called, "on_require should call patch! on matching integration"
    end
  end

  def test_on_require_respects_only_filter
    assert_in_fork do
      patch_called = false

      mock_integration = mock_integration_object(
        name: :excluded_lib,
        on_patch: -> { patch_called = true }
      )

      mock_registry = mock_registry_for("excluded_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, %i[openai anthropic])
      Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

      Braintrust::Contrib::Setup.on_require("excluded_lib")

      refute patch_called, "on_require should respect only filter"
    end
  end

  def test_on_require_respects_except_filter
    assert_in_fork do
      patch_called = false

      mock_integration = mock_integration_object(
        name: :excluded_lib,
        on_patch: -> { patch_called = true }
      )

      mock_registry = mock_registry_for("excluded_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
      Braintrust::Contrib::Setup.instance_variable_set(:@except, %i[excluded_lib])

      Braintrust::Contrib::Setup.on_require("excluded_lib")

      refute patch_called, "on_require should respect except filter"
    end
  end

  def test_on_require_skips_unavailable_integration
    assert_in_fork do
      patch_called = false

      mock_integration = mock_integration_object(
        name: :unavailable_lib,
        available: false,
        on_patch: -> { patch_called = true }
      )

      mock_registry = mock_registry_for("unavailable_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
      Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

      Braintrust::Contrib::Setup.on_require("unavailable_lib")

      refute patch_called, "on_require should skip unavailable integrations"
    end
  end

  def test_on_require_skips_incompatible_integration
    assert_in_fork do
      patch_called = false

      mock_integration = mock_integration_object(
        name: :incompatible_lib,
        compatible: false,
        on_patch: -> { patch_called = true }
      )

      mock_registry = mock_registry_for("incompatible_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
      Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

      Braintrust::Contrib::Setup.on_require("incompatible_lib")

      refute patch_called, "on_require should skip incompatible integrations"
    end
  end

  def test_on_require_returns_early_without_registry
    assert_in_fork do
      Braintrust::Contrib::Setup.instance_variable_set(:@registry, nil)

      # Should not raise
      Braintrust::Contrib::Setup.on_require("anything")
    end
  end

  def test_on_require_logs_errors_without_crashing
    assert_in_fork do
      error_logged = false

      mock_integration = mock_integration_object(
        name: :error_lib,
        on_patch: -> { raise "Patch error!" }
      )

      mock_registry = mock_registry_for("error_lib" => [mock_integration])

      Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
      Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
      Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

      Braintrust::Log.stub(:error, ->(_msg) { error_logged = true }) do
        Braintrust::Contrib::Setup.on_require("error_lib")
      end

      assert error_logged, "on_require should log errors without crashing"
    end
  end

  # --- with_reentrancy_guard ---

  def test_with_reentrancy_guard_prevents_nested_calls
    assert_in_fork do
      outer_ran = false
      inner_ran = false

      Braintrust::Contrib::Setup.with_reentrancy_guard do
        outer_ran = true
        Braintrust::Contrib::Setup.with_reentrancy_guard do
          inner_ran = true
        end
      end

      assert outer_ran, "outer block should run"
      refute inner_ran, "inner block should be skipped due to reentrancy guard"
    end
  end

  def test_with_reentrancy_guard_resets_after_completion
    assert_in_fork do
      Braintrust::Contrib::Setup.with_reentrancy_guard do
        # first call
      end

      second_call_ran = false
      Braintrust::Contrib::Setup.with_reentrancy_guard do
        second_call_ran = true
      end

      assert second_call_ran, "second call should run after first completes"
    end
  end

  def test_with_reentrancy_guard_logs_errors
    assert_in_fork do
      error_logged = false

      Braintrust::Log.stub(:error, ->(_msg) { error_logged = true }) do
        Braintrust::Contrib::Setup.with_reentrancy_guard do
          raise "Test error"
        end
      end

      assert error_logged, "with_reentrancy_guard should log errors"
    end
  end

  # --- install_railtie! ---

  def test_install_railtie_is_idempotent
    assert_in_fork do
      call_count = 0

      Braintrust::Contrib::Setup.stub(:require_relative, ->(path) { call_count += 1 if path == "rails/railtie" }) do
        Braintrust::Contrib::Setup.install_railtie!
        Braintrust::Contrib::Setup.install_railtie!
        Braintrust::Contrib::Setup.install_railtie!
      end

      assert_equal 1, call_count, "install_railtie! should only load railtie once"
    end
  end

  # --- install_require_hook! ---

  def test_install_require_hook_is_idempotent
    assert_in_fork do
      call_count = 0
      original_prepend = Kernel.method(:prepend)

      Kernel.define_singleton_method(:prepend) do |mod|
        call_count += 1 if mod == Braintrust::Contrib::RequireHook
        original_prepend.call(mod)
      end

      Braintrust::Contrib::Setup.install_require_hook!
      Braintrust::Contrib::Setup.install_require_hook!
      Braintrust::Contrib::Setup.install_require_hook!

      assert_equal 1, call_count, "install_require_hook! should only prepend once"
    end
  end

  # --- install_watcher_hook! ---

  def test_install_watcher_hook_is_idempotent
    assert_in_fork do
      Braintrust::Contrib::Setup.send(:install_watcher_hook!)
      Braintrust::Contrib::Setup.send(:install_watcher_hook!)

      # require still works
      require "json"
    end
  end

  def test_watcher_hook_triggers_on_require
    assert_in_fork do
      with_tmp_file(data: "# test file\n", filename: "watcher_test_lib", extension: ".rb") do |test_file|
        on_require_called = false
        test_lib_name = File.basename(test_file.path, ".rb")
        $LOAD_PATH.unshift(File.dirname(test_file.path))

        Braintrust::Contrib::Setup.instance_variable_set(:@registry, Braintrust::Contrib::Registry.instance)

        original_on_require = Braintrust::Contrib::Setup.method(:on_require)
        Braintrust::Contrib::Setup.define_singleton_method(:on_require) do |path|
          on_require_called = true if path.include?(test_lib_name)
          original_on_require.call(path)
        end

        Braintrust::Contrib::Setup.send(:install_watcher_hook!)
        require test_lib_name

        assert on_require_called, "on_require should be called"
      end
    end
  end

  def test_watcher_hook_upgrades_to_require_hook_when_zeitwerk_required
    skip "Test not applicable when Zeitwerk is already loaded" if defined?(::Zeitwerk)

    assert_in_fork do
      # Create a fake zeitwerk.rb that defines the Zeitwerk constant
      with_tmp_file(data: "module Zeitwerk; end\n", filename: "zeitwerk", extension: ".rb", exact_name: true) do |path|
        $LOAD_PATH.unshift(File.dirname(path))

        Braintrust::Contrib::Setup.send(:install_watcher_hook!)

        refute Braintrust::Contrib::Setup.require_hook_installed?, "require hook should not be installed yet"

        require "zeitwerk"

        assert Braintrust::Contrib::Setup.require_hook_installed?, "require hook should be installed after zeitwerk loads"
      end
    end
  end

  def test_watcher_hook_does_not_upgrade_for_non_zeitwerk_require_even_if_constant_exists
    skip "Test not applicable when Zeitwerk is already loaded" if defined?(::Zeitwerk)

    assert_in_fork do
      # Define Zeitwerk constant first
      Object.const_set(:Zeitwerk, Module.new)

      # Create an unrelated file (doesn't need exact_name since we're testing it DOESN'T match)
      with_tmp_file(data: "# unrelated\n", filename: "unrelated_lib", extension: ".rb", exact_name: true) do |path|
        $LOAD_PATH.unshift(File.dirname(path))

        Braintrust::Contrib::Setup.send(:install_watcher_hook!)

        refute Braintrust::Contrib::Setup.require_hook_installed?, "require hook should not be installed yet"

        require "unrelated_lib"

        refute Braintrust::Contrib::Setup.require_hook_installed?, "require hook should NOT be installed for non-zeitwerk require"
      end
    end
  end

  def test_watcher_hook_upgrades_to_railtie_when_rails_required
    skip "Test not applicable when Rails is already loaded" if defined?(::Rails::Railtie)

    assert_in_fork do
      # Create a fake rails.rb that defines the Rails::Railtie constant
      with_tmp_file(data: "module Rails; class Railtie; end; end\n", filename: "rails", extension: ".rb", exact_name: true) do |path|
        $LOAD_PATH.unshift(File.dirname(path))

        railtie_installed = false
        Braintrust::Contrib::Setup.define_singleton_method(:install_railtie!) do
          railtie_installed = true
          @railtie_installed = true
        end

        Braintrust::Contrib::Setup.send(:install_watcher_hook!)

        refute railtie_installed, "railtie should not be installed yet"

        require "rails"

        assert railtie_installed, "railtie should be installed after rails loads"
      end
    end
  end

  def test_watcher_hook_does_not_upgrade_for_non_rails_require_even_if_constant_exists
    skip "Test not applicable when Rails is already loaded" if defined?(::Rails::Railtie)

    assert_in_fork do
      # Define Rails::Railtie constant first
      Object.const_set(:Rails, Module.new)
      Rails.const_set(:Railtie, Class.new)

      # Create an unrelated file (doesn't need exact_name since we're testing it DOESN'T match)
      with_tmp_file(data: "# unrelated\n", filename: "another_lib", extension: ".rb", exact_name: true) do |path|
        $LOAD_PATH.unshift(File.dirname(path))

        railtie_installed = false
        Braintrust::Contrib::Setup.define_singleton_method(:install_railtie!) do
          railtie_installed = true
          @railtie_installed = true
        end

        Braintrust::Contrib::Setup.send(:install_watcher_hook!)

        refute railtie_installed, "railtie should not be installed yet"

        require "another_lib"

        refute railtie_installed, "railtie should NOT be installed for non-rails require"
      end
    end
  end

  # --- Integration tests with actual require hook ---

  def test_require_hook_instruments_matching_library
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

        Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
        Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
        Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

        Braintrust::Contrib::Setup.install_require_hook!
        require test_lib_name

        assert patch_called, "patch! should be called"
      end
    end
  end

  def test_require_hook_has_reentrancy_guard
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

          Braintrust::Contrib::Setup.instance_variable_set(:@registry, mock_registry)
          Braintrust::Contrib::Setup.instance_variable_set(:@only, nil)
          Braintrust::Contrib::Setup.instance_variable_set(:@except, nil)

          Braintrust::Contrib::Setup.install_require_hook!
          require reentrant_lib_name

          assert_equal [:patch_completed], require_calls_during_patch, "nested integration should not be patched"
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

  # Helper to stub Zeitwerk
  def with_mock_zeitwerk
    mock_zeitwerk = Module.new

    Object.stub_const(:Zeitwerk, mock_zeitwerk) do
      yield
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
  def mock_registry_for(mappings)
    registry = Object.new
    registry.define_singleton_method(:integrations_for_require_path) do |path|
      mappings.find { |lib_name, _| path.include?(lib_name) }&.last || []
    end
    registry
  end
end
