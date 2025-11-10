# frozen_string_literal: true

# Example demonstrating span filtering in Braintrust tracing
#
# Span filtering allows you to control which spans are exported to Braintrust.
# This is useful for reducing noise and cost by filtering out non-AI spans.
#
# To run this example:
#   export BRAINTRUST_API_KEY="your-api-key"
#   ruby examples/trace/span_filtering.rb

require "bundler/setup"
require "braintrust"

# Custom filter: keep spans with "important" in the name
important_filter = ->(span) do
  span.name.include?("important") ? 1 : 0  # 1 = keep, 0 = no influence
end

# Initialize Braintrust with AI span filtering + custom filter
Braintrust.init(
  blocking_login: true, # Wait for login to complete (needed for permalinks)
  filter_ai_spans: true, # Enable AI span filtering
  span_filter_funcs: [important_filter] # Add custom filter (has priority)
)

tracer = OpenTelemetry.tracer_provider.tracer("span-filtering-example")

tracer.in_span("span-filtering-demo") do |root_span|
  tracer.in_span("gen_ai.completion") do |ai_span|
    ai_span.set_attribute("gen_ai.model", "gpt-4")
    ai_span.set_attribute("gen_ai.prompt", "What is the capital of France?")

    # These child spans are NOT AI-related, so they will be filtered out
    tracer.in_span("database.query") do |db_span|
      sleep 0.01
    end

    tracer.in_span("cache.lookup") do |cache_span|
      sleep 0.005
    end

    # This span is NOT AI-related, but will be kept by custom filter
    tracer.in_span("important.validation") do |validation_span|
      sleep 0.005
    end

    # This child span IS AI-related, so it will be kept
    tracer.in_span("llm.token_counter") do |token_span|
      token_span.set_attribute("llm.token_count", 150)
    end

    ai_span.set_attribute("gen_ai.completion", "The capital of France is Paris.")
  end

  permalink = Braintrust::Trace.permalink(root_span)
  puts permalink
end

OpenTelemetry.tracer_provider.force_flush
OpenTelemetry.tracer_provider.shutdown
