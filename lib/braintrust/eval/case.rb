# frozen_string_literal: true

module Braintrust
  module Eval
    # Case represents a single test case in an evaluation
    # @attr input [Object] The input to the task
    # @attr expected [Object, nil] The expected output (optional)
    # @attr tags [Array<String>, nil] Optional tags for filtering/grouping
    # @attr metadata [Hash, nil] Optional metadata for the case
    # @attr origin [Hash, nil] Origin pointer for cases from remote sources (e.g., datasets).
    #   Contains: object_type, object_id, id, _xact_id, created
    Case = Struct.new(:input, :expected, :tags, :metadata, :origin, keyword_init: true)
  end
end
