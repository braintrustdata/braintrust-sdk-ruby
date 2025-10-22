# frozen_string_literal: true

require_relative "case"

module Braintrust
  module Eval
    # Cases wraps test case data (arrays or enumerables) and normalizes them to Case objects
    # Supports lazy evaluation for memory-efficient processing of large datasets
    class Cases
      include Enumerable

      # Create a new Cases wrapper
      # @param enumerable [Array, Enumerable] The test cases (hashes or Case objects)
      def initialize(enumerable)
        unless enumerable.respond_to?(:each)
          raise ArgumentError, "Cases must be enumerable (respond to :each)"
        end

        @enumerable = enumerable
      end

      # Iterate over cases, normalizing each to a Case object
      # @yield [Case] Each test case
      def each
        return enum_for(:each) unless block_given?

        @enumerable.each do |item|
          yield normalize_case(item)
        end
      end

      # Get the count of cases
      # Note: For lazy enumerators, this will force evaluation
      # @return [Integer]
      def count
        @enumerable.count
      end

      private

      # Normalize a case item to a Case object
      # @param item [Hash, Case] The case item
      # @return [Case]
      def normalize_case(item)
        case item
        when Case
          # Already a Case object
          item
        when Hash
          # Convert hash to Case object
          Case.new(**item)
        else
          raise ArgumentError, "Case must be a Hash or Case object, got #{item.class}"
        end
      end
    end
  end
end
