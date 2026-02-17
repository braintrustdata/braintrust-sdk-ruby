# frozen_string_literal: true

require_relative "api/datasets"
require_relative "api/functions"
require_relative "api/btql"

module Braintrust
  # API client for Braintrust REST API
  # Provides namespaced access to different API resources
  class API
    attr_reader :state

    def initialize(state: nil)
      @state = state || Braintrust.current_state
      raise Error, "No state available" unless @state
    end

    # Access to datasets API
    # @return [API::Datasets]
    def datasets
      @datasets ||= API::Datasets.new(self)
    end

    # Access to functions API
    # @return [API::Functions]
    def functions
      @functions ||= API::Functions.new(self)
    end

    # Login to Braintrust API (idempotent)
    # @return [self]
    def login
      @state.login
      self
    end

    # Generate a permalink URL to view an object in the Braintrust UI
    # This is for the /object endpoint (experiments, datasets, etc.)
    # For trace span permalinks, use Trace.permalink instead.
    # @param object_type [String] Type of object (e.g., "experiment", "dataset")
    # @param object_id [String] Object UUID
    # @return [String] Permalink URL
    def object_permalink(object_type:, object_id:)
      @state.object_permalink(object_type: object_type, object_id: object_id)
    end

    # Access to BTQL API
    # @return [API::BTQL]
    def btql
      @btql ||= API::BTQL.new(self)
    end
  end
end
