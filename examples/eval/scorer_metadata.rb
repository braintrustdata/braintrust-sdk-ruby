#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Scorer Metadata
#
# Scorers can return a Hash with :score and :metadata keys to attach
# structured context alongside the numeric score. The metadata is
# logged on the scorer's span and visible in the Braintrust UI for
# debugging and filtering.
#
# Usage:
#   bundle exec ruby examples/eval/scorer_metadata.rb

Braintrust.init

EXPECTED_TOOLS = {
  "What's the weather?" => {name: "get_weather", args: ["location"]},
  "Book a flight to Paris" => {name: "book_flight", args: ["destination", "date"]},
  "Send an email to Bob" => {name: "send_email", args: ["recipient", "subject", "body"]}
}

# Simulated tool-calling model
def pick_tool(input)
  case input
  when /weather/i then {name: "get_weather", args: ["location"]}
  when /flight/i then {name: "book_flight", args: ["destination"]} # missing "date"
  when /email/i then {name: "wrong_tool", args: []}
  else {name: "unknown", args: []}
  end
end

# Scorer that returns structured metadata explaining *why* a score was given
tool_accuracy = Braintrust::Scorer.new("tool_accuracy") { |expected:, output:|
  expected_name = expected[:name]
  actual_name = output[:name]
  expected_args = expected[:args]
  actual_args = output[:args]

  if actual_name != expected_name
    {
      score: 0.0,
      metadata: {
        failure_type: "wrong_tool",
        reason: "Expected tool '#{expected_name}' but got '#{actual_name}'"
      }
    }
  else
    missing_args = expected_args - actual_args
    if missing_args.empty?
      {score: 1.0, metadata: {failure_type: nil, reason: "Correct tool and arguments"}}
    else
      {
        score: 0.5,
        metadata: {
          failure_type: "missing_arguments",
          reason: "Correct tool '#{expected_name}' but missing args: #{missing_args.join(", ")}",
          missing_args: missing_args
        }
      }
    end
  end
}

Braintrust::Eval.run(
  project: "ruby-sdk-examples",
  experiment: "scorer-metadata-example",
  cases: EXPECTED_TOOLS.map { |input, expected| {input: input, expected: expected} },
  task: ->(input:) { pick_tool(input) },
  scorers: [tool_accuracy]
)

OpenTelemetry.tracer_provider.shutdown
