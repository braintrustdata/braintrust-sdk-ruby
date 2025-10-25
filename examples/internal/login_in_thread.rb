#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Non-blocking login with login_in_thread
#
# This example demonstrates how to:
# 1. Initialize Braintrust without blocking on login (uses login_in_thread internally)
# 2. Do other work while login happens in background
# 3. Create a span after work is done
# 4. Print a permalink to view the trace in Braintrust
#
# Usage:
#   bundle exec ruby examples/internal/login_in_thread.rb

# Initialize Braintrust - this returns immediately and logs in via background thread
Braintrust.init(blocking_login: false)

puts "Doing work while login completes in background..."
sleep 2

# Get a tracer
tracer = OpenTelemetry.tracer_provider.tracer("login-in-thread-example")

# Create a span
root_span = nil
tracer.in_span("examples/internal/login_in_thread.rb") do |span|
  root_span = span
  sleep 0.1
end

# Print permalink to view this trace in Braintrust
puts "\nView trace: #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown
