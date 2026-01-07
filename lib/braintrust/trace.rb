# frozen_string_literal: true

require_relative 'trace/otel/integration'

module Braintrust
  module Trace
    # WIP: Isolate OTel integration logic.
    #      This will make it easier to keep our API implementation agnostic
    #      in order to prevent breaking changes. It will also make it easier
    #      for us to add support for other frameworks in the future.

    # Setup on top of particular tracing framework
    def self.setup(state, tracer_provider: nil, exporter: nil)
      # ...we only support OTel today...
      OTel::Integration.setup(state, tracer_provider: tracer_provider, exporter: exporter)
    end

    def self.permalink(span)
      # ...TODO... call OTel
    end
  end
end
