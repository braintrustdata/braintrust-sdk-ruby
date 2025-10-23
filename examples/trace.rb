#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Enable Braintrust tracing and send a span manually
#
# This example demonstrates how to:
# 1. Initialize Braintrust with tracing enabled (automatically configures OpenTelemetry)
# 2. Create spans manually
# 3. Send the spans to Braintrust
#
# Usage:
#   bundle exec ruby examples/trace.rb

Braintrust.init(blocking_login: true)

# Get a tracer
tracer = OpenTelemetry.tracer_provider.tracer("my-app")

# Create a span manually
# Note: braintrust.parent, braintrust.org, and braintrust.app_url are automatically added!
root_span = nil
tracer.in_span("examples/trace.rb") do |span|
  root_span = span

  # Set custom attributes
  span.set_attribute("user.id", "123")
  span.set_attribute("operation.type", "manual_test")
  span.set_attribute("environment", "example")

  puts "Inside span - doing some work..."
  sleep 0.1

  # You can create nested spans - they also get Braintrust attributes automatically
  tracer.in_span("nested-operation") do |nested_span|
    nested_span.set_attribute("step", "1")
    puts "  Inside nested span..."
    sleep 0.05
  end
end

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Success! Trace sent to Braintrust!"
