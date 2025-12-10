#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Shared test data for parallelism benchmark examples
#
# This module provides test cases for benchmarking Eval.run parallelism.
# Both eval-parallel-benchmark.rb and eval-parallel-benchmark-sequential.rb
# use this data to ensure identical test conditions.
#
# Configure the number of test cases via BENCHMARK_CASES env var (default: 100):
#   BENCHMARK_CASES=100 bundle exec ruby examples/internal/eval-parallel-benchmark.rb

module EvalParallelBenchmarkData
  DEFAULT_COUNT = 100
  # Common fruits and vegetables for classification
  FRUITS = %w[
    apple banana orange grape mango strawberry blueberry raspberry
    pineapple watermelon cantaloupe honeydew kiwi papaya guava
    peach plum cherry apricot nectarine pear lemon lime grapefruit
    tangerine pomegranate fig date coconut lychee passionfruit
    dragonfruit starfruit persimmon mulberry blackberry cranberry
    gooseberry elderberry boysenberry loganberry acai tomato cucumber
    pepper squash eggplant pumpkin zucchini
  ].freeze

  VEGETABLES = %w[
    carrot broccoli spinach potato lettuce celery onion garlic
    cabbage cauliflower kale asparagus artichoke beet radish turnip
    parsnip rutabaga leek scallion shallot fennel chard collard endive
    arugula watercress radicchio okra pea bean corn mushroom
  ].freeze

  # Number of test cases (configurable via BENCHMARK_CASES env var)
  def self.count
    @count ||= (ENV["BENCHMARK_CASES"] || DEFAULT_COUNT).to_i
  end

  # Generate test cases by cycling through fruits and vegetables
  # Each item appears multiple times to reach the target count
  def self.test_cases
    cases = []

    # Alternate between fruits and vegetables to get even distribution
    all_items = []

    # Add fruits with their type
    FRUITS.each { |f| all_items << {word: f, type: "fruit"} }

    # Add vegetables with their type
    VEGETABLES.each { |v| all_items << {word: v, type: "vegetable"} }

    # Cycle through items until we have the target count
    count.times do |i|
      item = all_items[i % all_items.length]
      cases << {
        input: "Is '#{item[:word]}' a fruit or vegetable? Answer with just 'fruit' or 'vegetable'",
        expected: item[:type]
      }
    end

    cases
  end
end

# Parallelism Benchmark
#
# This benchmark runs test cases with configurable parallelism to measure
# the performance improvement from parallel execution.
#
# Environment variables:
#   OPENAI_API_KEY     - Required: OpenAI API key
#   BENCHMARK_PARALLELISM - Parallelism level (default: 1)
#   BENCHMARK_CASES    - Number of test cases (default: 100)
#
# Usage:
#   # Sequential (parallelism=1)
#   OPENAI_API_KEY=key bundle exec ruby examples/internal/eval-parallel-benchmark.rb
#
#   # Parallel (parallelism=10)
#   BENCHMARK_PARALLELISM=10 OPENAI_API_KEY=key bundle exec ruby examples/internal/eval-parallel-benchmark.rb
#
#   # Quick test (100 cases, parallelism=5)
#   BENCHMARK_CASES=100 BENCHMARK_PARALLELISM=5 OPENAI_API_KEY=key bundle exec ruby examples/internal/eval-parallel-benchmark.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

PARALLELISM = (ENV["BENCHMARK_PARALLELISM"] || 1).to_i
MODEL = "gpt-4o-mini"

puts "Parallelism Benchmark (parallelism=#{PARALLELISM})"
puts "=" * 50
puts "Test cases: #{EvalParallelBenchmarkData.count}"
puts "Model: #{MODEL}"
puts "Parallelism: #{PARALLELISM}"
puts

# Initialize Braintrust
Braintrust.init(blocking_login: true)

# Create OpenAI client and wrap for tracing
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
Braintrust::Trace::OpenAI.wrap(client)

# Task: Call OpenAI to classify fruit/vegetable
task = ->(input) {
  response = client.chat.completions.create(
    model: MODEL,
    messages: [{role: "user", content: input}],
    max_tokens: 5,
    temperature: 0
  )
  response.choices[0].message.content.downcase.strip
}

# Scorer: Exact match
exact_match = Braintrust::Eval.scorer("exact_match") do |_input, expected, output|
  (output == expected) ? 1.0 : 0.0
end

puts "Running evaluation..."
puts

# Run the evaluation
result = Braintrust::Eval.run(
  project: "ruby-sdk-internal-examples",
  experiment: "eval-parallel-benchmark-p#{PARALLELISM}",

  cases: EvalParallelBenchmarkData.test_cases,
  task: task,
  scorers: [exact_match],

  parallelism: PARALLELISM,

  tags: ["benchmark", "parallelism"],
  metadata: {
    parallelism: PARALLELISM,
    model: MODEL,
    test_cases: EvalParallelBenchmarkData.count
  }
)

# Print benchmark summary
puts
puts "Benchmark Summary"
puts "-" * 50
puts "  Total time: #{result.duration.round(2)}s"
puts "  Cases: #{EvalParallelBenchmarkData.count}"
puts "  Throughput: #{(EvalParallelBenchmarkData.count / result.duration).round(2)} cases/sec"
puts
puts "View results at:"
puts "  #{result.permalink}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts
puts "Done!"
