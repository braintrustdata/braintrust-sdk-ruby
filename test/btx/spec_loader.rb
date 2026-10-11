# frozen_string_literal: true

require "psych"

module Braintrust
  module BTX
    # Matcher value-objects produced by the spec's custom YAML tags.
    #
    # The spec uses three custom tags:
    #   !fn <name-or-expr>  — named predicate or Ruby lambda expression
    #   !starts_with <prefix> — string prefix check
    #   !or [...]           — at-least-one-of validator
    #
    # These are parsed into distinct matcher objects (not strings) so the
    # validator can dispatch on type.
    FnMatcher = Struct.new(:expr)
    StartsWithMatcher = Struct.new(:prefix)
    OrMatcher = Struct.new(:alternatives)
    # !gen <name> — a runtime-generated value (e.g. a per-run nonce). The
    # executor substitutes these before making API calls.
    GenMatcher = Struct.new(:name)

    # Value object representing a single llm_span_test spec file.
    LlmSpanSpec = Struct.new(
      :name, :type, :provider, :endpoint, :requests,
      :expected_brainstore_spans, :source_path, :variables, :headers,
      keyword_init: true
    ) do
      # @return [String] test id, "<provider>/<name>"
      def display_name
        "#{provider}/#{name}"
      end
    end

    # Loads BTX llm_span spec YAML files, handling the custom tags.
    module SpecLoader
      module_function

      # Load all specs under +root+, optionally filtered to +providers+.
      #
      # @param root [String] path to the test/llm_span directory
      # @param providers [Array<String>, nil] allow-list of provider dir names
      # @return [Array<LlmSpanSpec>] sorted by file path for determinism
      def load_specs(root, providers: nil)
        unless File.directory?(root)
          raise "BTX spec root not found: #{root}"
        end

        yaml_paths = Dir.glob(File.join(root, "**", "*.yaml")).sort

        yaml_paths.filter_map do |path|
          provider_dir = File.basename(File.dirname(path))
          next if providers && !providers.include?(provider_dir)

          data = parse_file(path)
          next unless data.is_a?(Hash)

          LlmSpanSpec.new(
            name: data["name"],
            type: data["type"],
            provider: data["provider"],
            endpoint: data["endpoint"],
            requests: data["requests"] || [],
            expected_brainstore_spans: data["expected_brainstore_spans"] || [],
            source_path: path,
            variables: data["variables"] || {},
            headers: data["headers"] || {}
          )
        end
      end

      # Parse a single YAML file, converting custom tags into matcher objects.
      #
      # @param path [String] file path
      # @return [Object] parsed structure with matcher objects substituted
      def parse_file(path)
        ast = Psych.parse(File.read(path), filename: path)
        return nil if ast.nil?
        convert(ast.root)
      end

      # Recursively convert a Psych AST node into Ruby values, intercepting
      # the BTX custom tags.
      def convert(node)
        case node
        when Psych::Nodes::Scalar
          convert_scalar(node)
        when Psych::Nodes::Sequence
          convert_sequence(node)
        when Psych::Nodes::Mapping
          convert_mapping(node)
        when Psych::Nodes::Alias
          # Anchors/aliases are not used by the spec; fall back to nil.
          nil
        end
      end

      def convert_scalar(node)
        case node.tag
        when "!fn"
          FnMatcher.new(node.value)
        when "!starts_with"
          StartsWithMatcher.new(node.value)
        when "!gen"
          GenMatcher.new(node.value)
        else
          # Use Psych's scalar coercion for proper typing (int, float, bool, nil).
          node.to_ruby
        end
      end

      def convert_sequence(node)
        items = node.children.map { |child| convert(child) }
        if node.tag == "!or"
          OrMatcher.new(items)
        else
          items
        end
      end

      def convert_mapping(node)
        result = {}
        node.children.each_slice(2) do |key_node, value_node|
          key = convert(key_node)
          result[key] = convert(value_node)
        end
        result
      end
    end
  end
end
