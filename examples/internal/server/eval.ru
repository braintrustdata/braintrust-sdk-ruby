#!/usr/bin/env ruby
# frozen_string_literal: true

# Dev Server - OpenAI Example (Internal)
#
# Like examples/server/eval.ru but uses OpenAI gpt-4o-mini for the task,
# so experiments show real LLM metrics (tokens, latency, cost).
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal openai \
#     rackup examples/internal/server/eval.ru -p 8300 -o 0.0.0.0

require "bundler/setup"
require "braintrust"
require "braintrust/server"
require "openai"

Braintrust.init
Braintrust.instrument!(:openai)

client = OpenAI::Client.new(api_key: ENV.fetch("OPENAI_API_KEY"))

food_classifier = Braintrust::Eval::Evaluator.new(
  task: ->(input) {
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      temperature: 0,
      max_tokens: 10,
      messages: [
        {role: "system", content: "Classify the food item as exactly one of: fruit, vegetable, unknown. Reply with only that single word, lowercase."},
        {role: "user", content: input.to_s}
      ]
    )
    response.choices.first.message.content.strip.downcase
  },
  scorers: [
    Braintrust::Eval.scorer("exact_match") { |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    }
  ]
)

class FoodCaseClassifier < Braintrust::Eval::Evaluator
  def task
    ->(input) {
      case input.to_s.downcase
      when /apple|banana|orange|grape/ then "fruit"
      when /carrot|broccoli|spinach/ then "vegetable"
      else "unknown"
      end
    }
  end

  def scorers
    [
      Braintrust::Eval.scorer("exact_match") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end
    ]
  end
end

text_summarizer = Braintrust::Eval::Evaluator.new(
  task: ->(input) {
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      temperature: 0,
      max_tokens: 100,
      messages: [
        {role: "system", content: "Summarize the following text in at most 10 words. Reply with only the summary."},
        {role: "user", content: input.to_s}
      ]
    )
    response.choices.first.message.content.strip
  },
  scorers: [
    Braintrust::Eval.scorer("length_check") { |input, expected, output|
      (output.to_s.length < input.to_s.length) ? 1.0 : 0.0
    }
  ],
  parameters: {
    "max_length" => {type: "number", default: 100, description: "Maximum summary length"}
  }
)

run Braintrust::Server::Rack.app(
  evaluators: {
    "food-classifier-llm" => food_classifier,
    "food-classifier-case" => FoodCaseClassifier.new,
    "text-summarizer" => text_summarizer
  }
)
