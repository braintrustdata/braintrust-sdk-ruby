# frozen_string_literal: true

require_relative "../vendor/mustache"

module Braintrust
  module Internal
    # Template rendering utilities for Mustache templates
    module Template
      module_function

      # Render a template string with variable substitution
      #
      # @param text [String] Template text to render
      # @param variables [Hash] Variables to substitute
      # @param format [String] Template format: "mustache", "none", or "nunjucks"
      # @param strict [Boolean] Raise error on missing variables (default: false)
      # @return [String] Rendered text
      def render(text, variables, format:, strict: false)
        return text unless text.is_a?(String)

        case format
        when "none"
          # No templating - return text unchanged
          text
        when "nunjucks"
          # Nunjucks is a UI-only feature in Braintrust
          raise Error, "Nunjucks templates are not supported in the Ruby SDK. " \
                       "Nunjucks only works in Braintrust playgrounds. " \
                       "Please use 'mustache' or 'none' template format, or invoke the prompt via the API proxy."
        when "mustache", "", nil
          # Default: Mustache templating
          if strict
            missing = find_missing_variables(text, variables)
            if missing.any?
              raise Error, "Missing required variables: #{missing.join(", ")}"
            end
          end

          Vendor::Mustache.render(text, variables)
        else
          raise Error, "Unknown template format: #{format.inspect}. " \
                       "Supported formats are 'mustache' and 'none'."
        end
      end

      # Find Mustache variables in template that are not provided
      #
      # @param text [String] Template text
      # @param variables [Hash] Available variables
      # @return [Array<String>] List of missing variable names
      def find_missing_variables(text, variables)
        # Extract {{variable}} and {{variable.path}} patterns
        # Mustache uses {{name}} syntax
        text.scan(/\{\{([^}#^\/!>]+)\}\}/).flatten.map(&:strip).uniq.reject do |var|
          resolve_variable(var, variables)
        end
      end

      # Check if a variable path exists in a hash
      #
      # @param path [String] Dot-separated variable path (e.g., "user.name")
      # @param variables [Hash] Variables to search
      # @return [Object, nil] The value if found, nil otherwise
      def resolve_variable(path, variables)
        parts = path.split(".")
        value = variables

        parts.each do |part|
          return nil unless value.is_a?(Hash)
          # Try both string and symbol keys
          value = value[part] || value[part.to_sym]
          return nil if value.nil?
        end

        value
      end

      # Convert hash keys to strings recursively
      #
      # @param hash [Hash] Hash with symbol or string keys
      # @return [Hash] Hash with all string keys
      def stringify_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end
    end
  end
end
