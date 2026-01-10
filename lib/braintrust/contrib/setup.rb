# frozen_string_literal: true

require_relative "../internal/env"

module Braintrust
  module Contrib
    # Automatic instrumentation setup for LLM libraries.
    #
    # Intercepts `require` calls to detect when LLM libraries are loaded, then patches
    # them automatically. The main challenge is doing this safely with zeitwerk (Rails'
    # autoloader) which also hooks into require.
    #
    # ## The Zeitwerk Problem
    #
    # Zeitwerk uses `alias_method :zeitwerk_original_require, :require`. If we prepend
    # to Kernel before zeitwerk loads, zeitwerk captures our method as its "original",
    # creating an infinite loop.
    #
    # ## Solution: Two-Phase Hook
    #
    #   ┌─────────────────────────────────────────────────────────────────────────┐
    #   │                         Setup.run! called                               │
    #   └─────────────────────────────────────────────────────────────────────────┘
    #                                      │
    #            ┌─────────────────────────┼─────────────────────────┐
    #            ▼                         ▼                         ▼
    #   ┌─────────────────┐     ┌─────────────────────┐    ┌─────────────────────┐
    #   │ Rails loaded?   │     │ Zeitwerk loaded?    │    │ Neither loaded yet  │
    #   │ (Rails::Railtie)│     │                     │    │                     │
    #   └────────┬────────┘     └──────────┬──────────┘    └──────────┬──────────┘
    #            │                         │                          │
    #            ▼                         ▼                          ▼
    #   ┌─────────────────┐     ┌─────────────────────┐    ┌─────────────────────┐
    #   │ Install Railtie │     │ Install prepend     │    │ Install watcher     │
    #   │ (after_init)    │     │ hook directly       │    │ hook (alias_method) │
    #   └─────────────────┘     └─────────────────────┘    └──────────┬──────────┘
    #            │                         │                          │
    #            │                         │               ┌──────────┴──────────┐
    #            │                         │               ▼                     ▼
    #            │                         │      ┌──────────────┐    ┌──────────────────┐
    #            │                         │      │ Rails loads? │    │ Zeitwerk loads?  │
    #            │                         │      │ → Railtie    │    │ → Prepend hook   │
    #            │                         │      └──────────────┘    └──────────────────┘
    #            │                         │               │                     │
    #            ▼                         ▼               ▼                     ▼
    #   ┌─────────────────────────────────────────────────────────────────────────┐
    #   │                    LLM library loads → patch!                           │
    #   └─────────────────────────────────────────────────────────────────────────┘
    #
    # The watcher hook uses alias_method which zeitwerk captures harmlessly (alias
    # chains work correctly). Once zeitwerk/Rails loads, we upgrade to the better
    # approach: prepend (takes precedence, `super` chains through zeitwerk) or
    # Railtie (patches after all gems loaded via after_initialize).
    #
    module Setup
      REENTRANCY_KEY = :braintrust_in_require_hook

      class << self
        # Main entry point. Call once per process.
        def run!
          unless Internal::Env.auto_instrument
            Braintrust::Log.debug("Contrib::Setup: auto-instrumentation disabled via environment")
            return
          end

          @registry = Contrib::Registry.instance
          @only = Internal::Env.instrument_only
          @except = Internal::Env.instrument_except

          if defined?(::Rails::Railtie)
            Braintrust::Log.debug("Contrib::Setup: using Rails railtie hook")
            install_railtie!
          elsif defined?(::Zeitwerk)
            Braintrust::Log.debug("Contrib::Setup: using require hook (zeitwerk detected)")
            install_require_hook!
          else
            Braintrust::Log.debug("Contrib::Setup: using watcher hook")
            install_watcher_hook!
          end
        end

        # Called after each require to check if we should patch anything.
        def on_require(path)
          return unless @registry

          @registry.integrations_for_require_path(path).each do |integration|
            next unless integration.available? && integration.compatible?
            next if @only && !@only.include?(integration.integration_name)
            next if @except&.include?(integration.integration_name)

            Braintrust::Log.debug("Contrib::Setup: patching #{integration.integration_name}")
            integration.patch!
          end
        rescue => e
          Braintrust::Log.error("Auto-instrument failed: #{e.message}")
        end

        # Execute block with reentrancy protection (prevents infinite loops).
        def with_reentrancy_guard
          return if Thread.current[REENTRANCY_KEY]
          Thread.current[REENTRANCY_KEY] = true
          yield
        rescue => e
          Braintrust::Log.error("Auto-instrument failed: #{e.message}")
        ensure
          Thread.current[REENTRANCY_KEY] = false
        end

        def railtie_installed? = @railtie_installed
        def require_hook_installed? = @require_hook_installed

        def install_railtie!
          return if @railtie_installed
          @railtie_installed = true
          require_relative "rails/railtie"
        end

        def install_require_hook!
          return if @require_hook_installed
          @require_hook_installed = true
          Kernel.prepend(RequireHook)
        end

        private

        def install_watcher_hook!
          return if Kernel.private_method_defined?(:braintrust_watcher_require)

          Kernel.module_eval do
            alias_method :braintrust_watcher_require, :require

            define_method(:require) do |path|
              result = braintrust_watcher_require(path)

              # Detect Rails/zeitwerk loading and upgrade hook strategy.
              # IMPORTANT: Only check when the gem itself finishes loading (path match),
              # not on every require where the constant happens to be defined.
              # Installing too early (during gem init) breaks the alias_method chain.
              if (path == "rails" || path.include?("railties")) &&
                  defined?(::Rails::Railtie) && !Braintrust::Contrib::Setup.railtie_installed?
                Braintrust::Contrib::Setup.install_railtie!
              elsif (path == "zeitwerk" || path.end_with?("/zeitwerk.rb")) &&
                  defined?(::Zeitwerk) && !Braintrust::Contrib::Setup.require_hook_installed?
                Braintrust::Contrib::Setup.install_require_hook!
              end

              Braintrust::Contrib::Setup.with_reentrancy_guard do
                Braintrust::Contrib::Setup.on_require(path)
              end

              result
            end
          end
        end
      end
    end

    # Prepend module for require interception.
    # Only installed AFTER zeitwerk loads to avoid alias_method loop.
    module RequireHook
      def require(path)
        result = super
        Setup.with_reentrancy_guard { Setup.on_require(path) }
        result
      end
    end
  end
end
