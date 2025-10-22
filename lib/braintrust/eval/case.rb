# frozen_string_literal: true

module Braintrust
  module Eval
    # Case represents a single test case in an evaluation
    # @attr input [Object] The input to the task
    # @attr expected [Object, nil] The expected output (optional)
    # @attr tags [Array<String>, nil] Optional tags for filtering/grouping
    # @attr metadata [Hash, nil] Optional metadata for the case
    Case = Struct.new(:input, :expected, :tags, :metadata, keyword_init: true)
  end
end
