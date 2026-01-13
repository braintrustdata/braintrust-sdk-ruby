# frozen_string_literal: true

require "singleton"

module Braintrust
  module Contrib
    # Thread-safe singleton registry for integrations.
    # Provides registration, lookup, and require-path mapping for auto-instrumentation.
    class Registry
      include Singleton

      def initialize
        @integrations = {}
        @require_path_map = nil # Lazy cache
        @mutex = Mutex.new
      end

      # Register an integration class with the registry.
      # @param integration_class [Class] The integration class to register
      def register(integration_class)
        @mutex.synchronize do
          @integrations[integration_class.integration_name] = integration_class
          @require_path_map = nil # Invalidate cache
        end
      end

      # Look up an integration by name.
      # @param name [Symbol, String] The integration name
      # @return [Class, nil] The integration class, or nil if not found
      def [](name)
        @integrations[name.to_sym]
      end

      # Get all registered integrations.
      # @return [Array<Class>] All registered integration classes
      def all
        @integrations.values
      end

      # Get all available integrations (target library is loaded).
      # @return [Array<Class>] Available integration classes
      def available
        @integrations.values.select(&:available?)
      end

      # Iterate over all registered integrations.
      # @yield [Class] Each registered integration class
      def each(&block)
        @integrations.values.each(&block)
      end

      # Returns integrations associated with a require path.
      # Thread-safe with double-checked locking for performance.
      # @param path [String] The require path (e.g., "openai", "anthropic")
      # @return [Array<Class>] Integrations matching the require path
      def integrations_for_require_path(path)
        map = @require_path_map
        if map.nil?
          map = @mutex.synchronize do
            @require_path_map ||= build_require_path_map
          end
        end

        path_str = path.to_s
        basename = File.basename(path_str, ".rb")

        # Quick check: is this basename even in our map?
        return EMPTY_ARRAY unless map.key?(basename)

        # Only match top-level requires or gem entry points.
        # Avoid matching internal subpaths (e.g., ruby_llm/providers/anthropic).
        return EMPTY_ARRAY unless gem_entry_point?(path_str, basename)

        map.fetch(basename, EMPTY_ARRAY)
      end

      private

      EMPTY_ARRAY = [].freeze

      # Check if this is a gem entry point require.
      # @param path [String] Full require path
      # @param basename [String] File basename without extension
      # @return [Boolean]
      def gem_entry_point?(path, basename)
        # Direct require like `require 'anthropic'` - no directory separators
        return true unless path.include?("/")

        # Full path to gem entry point: /gems/anthropic-1.0.0/lib/anthropic.rb
        # The basename appears in both the gem directory name AND as the final file
        path.match?(%r{/#{Regexp.escape(basename)}[^/]*/lib/#{Regexp.escape(basename)}(\.rb)?$})
      end

      def build_require_path_map
        map = {}
        @integrations.each_value do |integration|
          integration.require_paths.each do |req|
            map[req] ||= []
            map[req] << integration
          end
        end
        map.each_value(&:freeze)
        map.freeze
      end
    end
  end
end
