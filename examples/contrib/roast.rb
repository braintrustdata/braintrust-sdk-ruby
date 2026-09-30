#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "roast"
require "opentelemetry/sdk"
require "tmpdir"

# Usage:
#   OPENAI_API_KEY=... BRAINTRUST_API_KEY=... bundle exec appraisal roast ruby examples/contrib/roast.rb

unless ENV["OPENAI_API_KEY"] && ENV["BRAINTRUST_API_KEY"]
  warn "OPENAI_API_KEY and BRAINTRUST_API_KEY are required"
  exit 1
end

# In a long-running app, plain Braintrust.init is sufficient. Blocking login and
# shutdown are useful here because this example exits immediately.
Braintrust.init(blocking_login: true)

tracer = OpenTelemetry.tracer_provider.tracer("roast-example")
root_span = nil

Dir.mktmpdir("roast-example") do |dir|
  path = File.join(dir, "workflow.rb")
  File.write(path, <<~ROAST)
    config do
      chat(:answer) { no_show_stats! }
    end
    execute do
      ruby(:question) { "What is the capital of France? Answer in three words or fewer." }
      chat(:answer) { ruby!(:question).value }
    end
  ROAST

  tracer.in_span("Roast example") do |span|
    root_span = span
    Roast::Workflow.from_file(path, Roast::WorkflowParams.new([], [], {}))
  end
end

puts "View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"
OpenTelemetry.tracer_provider.shutdown
