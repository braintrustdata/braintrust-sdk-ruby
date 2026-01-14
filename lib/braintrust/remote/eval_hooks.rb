# frozen_string_literal: true

module Braintrust
  module Remote
    # Hooks provided to the task function during evaluation
    # Allows access to parameters and reporting progress
    class EvalHooks
      attr_reader :parameters, :metadata

      def initialize(parameters: {}, metadata: {}, stream_callback: nil)
        @parameters = parameters
        @metadata = metadata
        @stream_callback = stream_callback
      end

      # Report progress during task execution
      # This is used for streaming updates to the playground
      #
      # @param event [Hash] Progress event data
      def report_progress(event)
        @stream_callback&.call(event)
      end

      # Add metadata to the current evaluation
      #
      # @param key [String, Symbol] Metadata key
      # @param value [Object] Metadata value
      def set_metadata(key, value)
        @metadata[key.to_sym] = value
      end
    end
  end
end
