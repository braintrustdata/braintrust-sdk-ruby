# frozen_string_literal: true

require_relative "api/datasets"
require_relative "api/functions"

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
  end
end
