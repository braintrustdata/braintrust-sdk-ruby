#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "roast"
require "opentelemetry/sdk"

# Usage:
#   OPENAI_API_KEY=... BRAINTRUST_API_KEY=... bundle exec appraisal roast ruby examples/contrib/roast/basic.rb

unless ENV["OPENAI_API_KEY"] && ENV["BRAINTRUST_API_KEY"]
  warn "OPENAI_API_KEY and BRAINTRUST_API_KEY are required"
  exit 1
end

# In a long-running app, plain Braintrust.init is sufficient. Blocking login and
# shutdown are useful here because this example exits immediately.
Braintrust.init(blocking_login: true)

tracer = OpenTelemetry.tracer_provider.tracer("roast-example")
root_span = nil

tracer.in_span("Roast example") do |span|
  root_span = span
  Roast::Workflow.from_file(File.join(__dir__, "workflow.rb"), Roast::WorkflowParams.new([], [], {}))
end

puts "View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"
OpenTelemetry.tracer_provider.shutdown
