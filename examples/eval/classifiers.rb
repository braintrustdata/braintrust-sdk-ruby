#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Classifiers
#
# Classifiers categorize and label eval outputs. Unlike scorers (which return
# numeric 0-1 values), classifiers return structured Classification items —
# each with an :id, an optional :label, and optional :metadata.
#
# Results are stored as a dictionary keyed by classifier name:
#
#   { "sentiment" => [{ id: "positive", label: "Positive" }] }
#
# Three patterns are shown:
#
#   1. Block-based (Braintrust::Classifier.new):
#      Returns a single Classification hash. Good for concise, one-off classifiers.
#
#   2. Multi-label block-based:
#      Returns an Array of Classification hashes — useful when a single
#      classifier assigns multiple labels to the same output.
#
#   3. Class-based (include Braintrust::Classifier):
#      Define a class with a #call method. Good for reusable classifiers
#      that carry their own logic and state.
#
# Classifiers and scorers run independently. You can use both together, or
# use only classifiers when you don't need numeric scores.
#
# Usage:
#   bundle exec ruby examples/eval/classifiers.rb

Braintrust.init

# ---------------------------------------------------------------------------
# Test cases: customer support messages
# ---------------------------------------------------------------------------
MESSAGES = [
  {input: "Hi! I just wanted to say thank you, the product is amazing!"},
  {input: "I've been waiting 2 weeks for my order. This is unacceptable!"},
  {input: "How do I reset my password? I can't find the option anywhere."},
  {input: "The item arrived damaged. I need a refund immediately."},
  {input: "Just checking in — any update on my ticket #4821?"}
]

# ---------------------------------------------------------------------------
# Simulated task: generate a support response (replace with a real LLM call)
# ---------------------------------------------------------------------------
def generate_response(message)
  case message
  when /thank/i then "You're welcome! So glad you're enjoying it."
  when /waiting|order/i then "I sincerely apologise for the delay. Let me look into this right away."
  when /password|reset/i then "To reset your password, go to Settings > Account > Reset Password."
  when /damaged|refund/i then "I'm sorry to hear that. I'll process your refund immediately."
  else "Thanks for reaching out! Let me check on that for you."
  end
end

# ---------------------------------------------------------------------------
# Pattern 1: block-based single-label classifier
#
# Classifies each message into a single intent category.
# Declare only the kwargs you need — extras are filtered automatically.
# ---------------------------------------------------------------------------
intent_classifier = Braintrust::Classifier.new("intent") do |input:|
  id = case input
  when /thank/i then "praise"
  when /waiting|order|update/i then "follow_up"
  when /password|reset|find/i then "how_to"
  when /damaged|refund/i then "complaint"
  else "other"
  end

  {name: "intent", id: id, label: id.tr("_", " ").capitalize}
end

# ---------------------------------------------------------------------------
# Pattern 2: block-based multi-label classifier
#
# A single classifier can return an Array to assign multiple labels.
# All items sharing the same :name are grouped into the same results array.
# ---------------------------------------------------------------------------
tone_classifier = Braintrust::Classifier.new("tone") do |input:|
  labels = []
  labels << {name: "tone", id: "urgent", label: "Urgent"} if input.match?(/immediately|unacceptable|waiting/i)
  labels << {name: "tone", id: "polite", label: "Polite"} if input.match?(/please|thank|just checking/i)
  labels << {name: "tone", id: "frustrated", label: "Frustrated"} if input.match?(/unacceptable|damaged|waiting/i)
  labels << {name: "tone", id: "neutral", label: "Neutral"} if labels.empty?
  labels
end

# ---------------------------------------------------------------------------
# Pattern 3: class-based classifier
#
# Include Braintrust::Classifier and define #call with keyword args.
# The class name is snake_cased to derive the default classifier name
# (ResponseQualityClassifier -> "response_quality_classifier").
# Override #name to customise it.
# ---------------------------------------------------------------------------
class ResponseQualityClassifier
  include Braintrust::Classifier

  def name
    "response_quality"
  end

  def call(input:, output:)
    word_count = output.to_s.split.length

    id = if output.to_s.strip.empty?
      "no_response"
    elsif word_count < 5
      "too_short"
    elsif output.match?(/immediately|right away|look into/i)
      "action_oriented"
    else
      "informational"
    end

    {
      name: "response_quality",
      id: id,
      label: id.tr("_", " ").capitalize,
      metadata: {word_count: word_count}
    }
  end
end

# ---------------------------------------------------------------------------
# Run the eval — classifiers only (no numeric scores needed here)
# ---------------------------------------------------------------------------
Braintrust::Eval.run(
  project: "ruby-sdk-examples",
  experiment: "classifiers-example",
  cases: MESSAGES,
  task: ->(input:) { generate_response(input) },
  classifiers: [intent_classifier, tone_classifier, ResponseQualityClassifier.new]
)

OpenTelemetry.tracer_provider.shutdown
