# frozen_string_literal: true

require_relative "internal/callable"

module Braintrust
  # Classifier wraps a classification function that categorizes and labels eval outputs.
  #
  # Unlike scorers (which return numeric 0-1 values), classifiers return structured
  # {Classification} items with an id and optional label and metadata.
  #
  # Use inline with a block (keyword args):
  #   classifier = Classifier.new("category") { |output:| {name: "category", id: "greeting", label: "Greeting"} }
  #
  # Or include in a class and define #call with keyword args:
  #   class CategoryClassifier
  #     include Braintrust::Classifier
  #
  #     def call(output:)
  #       {name: "category", id: "greeting", label: "Greeting"}
  #     end
  #   end
  #
  # Classifiers may return a single Classification hash, an Array of them, or nil
  # (meaning no classifications for this case).
  module Classifier
    DEFAULT_NAME = "classifier"

    # @param base [Class] the class including Classifier
    def self.included(base)
      base.include(Callable)
    end

    # Create a block-based classifier.
    #
    # @param name [String, nil] optional name (defaults to "classifier")
    # @param block [Proc] the classification implementation; declare only the keyword
    #   args you need. Extra kwargs are filtered out automatically.
    #
    #   Supported kwargs: +input:+, +expected:+, +output:+, +metadata:+, +trace:+, +parameters:+
    # @return [Classifier::Block]
    # @raise [ArgumentError] if the block has unsupported arity
    def self.new(name = nil, &block)
      Block.new(name: name || DEFAULT_NAME, &block)
    end

    # Included into classes that +include Classifier+. Prepends KeywordFilter and
    # ClassificationNormalizer so #call receives only declared kwargs and always returns
    # Array<Hash>. Also provides a default #name and #call_parameters.
    module Callable
      # Normalizes the raw return value of #call into Array<Hash>.
      # Nested inside Callable because it depends on #name which Callable provides.
      module ClassificationNormalizer
        # @return [Array<Hash>] normalized classification hashes with :name, :id, and optional :label, :metadata keys
        def call(**kwargs)
          normalize_classification_result(super)
        end

        private

        # @param result [Hash, Array<Hash>, nil] raw return value from #call
        # @return [Array<Hash>] zero or more classification hashes with :name, :id keys
        # @raise [ArgumentError] if any item is not a non-empty object
        def normalize_classification_result(result)
          case result
          when nil then []
          when Array then result.map { |item| normalize_classification_item(item) }
          when Hash then [normalize_classification_item(result)]
          else
            raise ArgumentError, "When returning structured classifier results, each classification must be a non-empty object. Got: #{result.inspect}"
          end
        end

        # Fills in missing :name from the classifier, validates :id.
        # @param item [Hash] a classification hash
        # @return [Hash] the item with :name defaulted and validated
        # @raise [ArgumentError] if item is not a non-empty Hash
        def normalize_classification_item(item)
          unless item.is_a?(Hash) && !item.empty?
            raise ArgumentError, "When returning structured classifier results, each classification must be a non-empty object. Got: #{item.inspect}"
          end

          # :name defaults to the classifier's resolved name when missing, empty, or non-string
          unless item[:name].is_a?(String) && !item[:name].empty?
            item = item.merge(name: name)
          end

          item
        end
      end

      # Infrastructure modules prepended onto every classifier class.
      # Used both to set up the ancestor chain and to skip past them in
      # #call_parameters so KeywordFilter sees the real call signature.
      PREPENDED = [Internal::Callable::KeywordFilter, ClassificationNormalizer].freeze

      # @param base [Class] the class including Callable
      def self.included(base)
        PREPENDED.each { |mod| base.prepend(mod) }
      end

      # Default name derived from the class name (e.g. CategoryClassifier -> "category_classifier").
      # @return [String]
      def name
        klass = self.class.name&.split("::")&.last
        return Classifier::DEFAULT_NAME unless klass
        klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Provides KeywordFilter with the actual call signature of the subclass.
      # Walks past PREPENDED modules in the ancestor chain so that user-defined
      # #call keyword params are correctly introspected.
      # Block overrides this to point directly at @block.parameters.
      # @return [Array<Array>] parameter list
      def call_parameters
        meth = method(:call)
        meth = meth.super_method while meth.super_method && PREPENDED.include?(meth.owner)
        meth.parameters
      end
    end

    # Block-based classifier. Stores a Proc and delegates #call to it.
    # Includes Classifier so it satisfies +Classifier ===+ checks.
    # Exposes #call_parameters so KeywordFilter can introspect the block's
    # declared kwargs rather than Block#call's **kwargs signature.
    class Block
      include Classifier

      # @return [String]
      attr_reader :name

      # @param name [String] classifier name
      # @param block [Proc] classification implementation; must use keyword args or zero-arity
      # @raise [ArgumentError] if the block uses positional params
      def initialize(name: DEFAULT_NAME, &block)
        @name = name
        params = block.parameters
        unless Internal::Callable::KeywordFilter.has_any_keywords?(params) || block.arity == 0
          raise ArgumentError, "Classifier block must use keyword args (got arity #{block.arity})"
        end
        @block = block
      end

      # @param kwargs [Hash] keyword arguments (filtered by KeywordFilter)
      # @return [Array<Hash>] normalized classification results
      def call(**kwargs)
        @block.call(**kwargs)
      end

      # Exposes the block's parameter list so KeywordFilter can filter
      # kwargs to match the block's declared keywords.
      # @return [Array<Array>] parameter list from Proc#parameters
      def call_parameters
        @block.parameters
      end
    end
  end
end
