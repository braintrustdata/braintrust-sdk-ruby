#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Multi-Score Scorers
#
# A scorer can return an Array of score hashes to emit multiple named metrics
# from a single scorer call. Each hash must have a :name and :score key; an
# optional :metadata key attaches structured context to that metric.
#
# This is useful when several dimensions of quality (e.g. correctness,
# completeness, format) can be computed together — sharing one inference call
# or one pass over the output — rather than running separate scorers.
#
# Two patterns are shown:
#
#   1. Block-based (Braintrust::Scorer.new):
#      Pass a block that returns an Array. Good for concise, one-off scorers.
#
#   2. Class-based (include Braintrust::Scorer):
#      Define a class with a #call method. Good for reusable scorers that
#      share helper logic across multiple metrics.
#
# Usage:
#   bundle exec ruby examples/eval/multi_score.rb

Braintrust.init

# ---------------------------------------------------------------------------
# Task: summarise a list of facts
# ---------------------------------------------------------------------------
FACTS = {
  "The sky is blue and clouds are white." => {
    key_terms: %w[sky blue clouds white],
    max_words: 10
  },
  "Ruby was created by Matz in 1995." => {
    key_terms: %w[ruby matz 1995],
    max_words: 8
  },
  "The Pacific Ocean is the largest ocean on Earth." => {
    key_terms: %w[pacific largest ocean earth],
    max_words: 10
  }
}

# Simulated summariser (replace with a real LLM call in production)
def summarise(text)
  # Naive: drop words over the limit and lowercase
  text.split.first(8).join(" ").downcase
end

# ---------------------------------------------------------------------------
# Pattern 1: block-based multi-score scorer
#
# Returns three metrics in one pass:
#   - coverage:    fraction of key terms present in the summary
#   - conciseness: 1.0 if under the word limit, else 0.0
#   - lowercase:   1.0 if the summary is fully lowercased
# ---------------------------------------------------------------------------
summary_quality = Braintrust::Scorer.new("summary_quality") do |output:, expected:|
  words = output.to_s.downcase.split
  key_terms = expected[:key_terms]
  max_words = expected[:max_words]

  covered = key_terms.count { |t| words.include?(t) }
  coverage_score = key_terms.empty? ? 1.0 : covered.to_f / key_terms.size

  [
    {
      name: "coverage",
      score: coverage_score,
      metadata: {covered: covered, total: key_terms.size, missing: key_terms - words}
    },
    {
      name: "conciseness",
      score: (words.size <= max_words) ? 1.0 : 0.0,
      metadata: {word_count: words.size, limit: max_words}
    },
    {
      name: "lowercase",
      score: (output.to_s == output.to_s.downcase) ? 1.0 : 0.0
    }
  ]
end

# ---------------------------------------------------------------------------
# Pattern 2: class-based multi-score scorer
#
# Include Braintrust::Scorer and define #call. The class name is used as the
# scorer name by default; override #name to customise it.
#
# Returns two metrics:
#   - ends_with_period: checks punctuation
#   - no_first_person:  checks for avoided first-person pronouns
# ---------------------------------------------------------------------------
class StyleChecker
  include Braintrust::Scorer

  FIRST_PERSON = %w[i me my myself we us our].freeze

  def call(output:, **)
    text = output.to_s
    words = text.downcase.split(/\W+/)
    fp_words = words & FIRST_PERSON

    [
      {
        name: "ends_with_period",
        score: text.strip.end_with?(".") ? 1.0 : 0.0
      },
      {
        name: "no_first_person",
        score: fp_words.empty? ? 1.0 : 0.0,
        metadata: {found: fp_words}
      }
    ]
  end
end

Braintrust::Eval.run(
  project: "ruby-sdk-examples",
  experiment: "multi-score-example",
  cases: FACTS.map { |text, expected| {input: text, expected: expected} },
  task: ->(input:) { summarise(input) },
  scorers: [summary_quality, StyleChecker.new]
)

OpenTelemetry.tracer_provider.shutdown
