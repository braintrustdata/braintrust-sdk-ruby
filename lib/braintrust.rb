# frozen_string_literal: true

require_relative "braintrust/version"

# Braintrust Ruby SDK
#
# OpenTelemetry-based SDK for Braintrust with tracing, OpenAI integration, and evals.
#
# @example Initialize with global state
#   Braintrust.init(
#     api_key: ENV['BRAINTRUST_API_KEY'],
#     project: "my-project"
#   )
#
# @example Initialize with explicit state
#   state = Braintrust.init(
#     api_key: ENV['BRAINTRUST_API_KEY'],
#     set_global: false
#   )
module Braintrust
  class Error < StandardError; end

  # TODO: Implementation coming in Phase 2
end
