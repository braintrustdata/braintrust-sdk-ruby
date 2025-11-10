#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "braintrust/trace/attachment"
require "opentelemetry/sdk"
require "json"
require "tempfile"

# Example: Using Attachments with Braintrust Traces
#
# This example demonstrates how to manually create and log attachments (images,
# PDFs, etc.) in Braintrust traces. Attachments are useful for multimodal AI
# applications, especially when working with vision models.
#
# Most users won't need to do this manually, as the OpenAI and Anthropic
# wrappers automatically handle attachment conversion. This example shows the
# lower-level attachment API.
#
# Usage:
#   bundle exec ruby examples/trace/trace_attachments.rb

# Helper function to create a test PNG image (10x10 red square)
def create_test_image_bytes
  [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x0a,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x02, 0x50, 0x58, 0xea, 0x00, 0x00, 0x00,
    0x12, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xf8, 0xcf, 0xc0, 0x80,
    0x07, 0x31, 0x8c, 0x4a, 0x63, 0x43, 0x00, 0xb7, 0xca, 0x63, 0x9d, 0xd6,
    0xd5, 0xef, 0x74, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
    0x42, 0x60, 0x82
  ].pack("C*")
end

# Helper function to log an attachment in a span
def log_attachment(span, attachment)
  messages = [
    {
      role: "user",
      content: [
        {
          type: "text",
          text: "Example with attachment"
        },
        attachment.to_h
      ]
    }
  ]

  span.set_attribute("braintrust.input_json", JSON.generate(messages))
end

# Initialize Braintrust
Braintrust.init(blocking_login: true)

# Get a tracer
tracer = OpenTelemetry.tracer_provider.tracer("attachments-example")

# Create a parent span to wrap all examples
root_span = nil
tracer.in_span("examples/trace/trace_attachments.rb") do |span|
  root_span = span

  # Example 1: Create attachment from bytes
  puts "Example 1: from_bytes"
  tracer.in_span("attachment.from_bytes") do |example_span|
    image_bytes = create_test_image_bytes
    att = Braintrust::Trace::Attachment.from_bytes(
      Braintrust::Trace::Attachment::IMAGE_PNG,
      image_bytes
    )

    puts "  Created attachment from #{image_bytes.bytesize} bytes"
    log_attachment(example_span, att)
  end

  # Example 2: Create attachment from file
  puts "\nExample 2: from_file"
  tracer.in_span("attachment.from_file") do |example_span|
    # Create a temporary file
    temp_file = Tempfile.new(["test-image", ".png"])
    begin
      temp_file.binmode
      temp_file.write(create_test_image_bytes)
      temp_file.flush
      temp_file.close

      att = Braintrust::Trace::Attachment.from_file(
        Braintrust::Trace::Attachment::IMAGE_PNG,
        temp_file.path
      )

      puts "  Created attachment from file"
      log_attachment(example_span, att)
    ensure
      temp_file.unlink
    end
  end

  # Example 3: Create attachment from URL
  puts "\nExample 3: from_url"
  tracer.in_span("attachment.from_url") do |example_span|
    # Fetch image from Braintrust's GitHub avatar
    url = "https://avatars.githubusercontent.com/u/109710255?s=200&v=4"

    begin
      att = Braintrust::Trace::Attachment.from_url(url)
      puts "  Fetched attachment from URL"
      log_attachment(example_span, att)
    rescue => e
      puts "  Failed to fetch URL: #{e.message}"
    end
  end

  # Example 4: Use attachment in a vision task (manual span logging)
  puts "\nExample 4: Manual span with attachment (vision task)"
  tracer.in_span("vision.analyze_image") do |vision_span|
    # Create attachment from test data
    image_bytes = create_test_image_bytes
    att = Braintrust::Trace::Attachment.from_bytes(
      Braintrust::Trace::Attachment::IMAGE_PNG,
      image_bytes
    )

    # Construct a message with text and image (similar to OpenAI/Anthropic format)
    messages = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "What's in this image? Describe it in detail."
          },
          att.to_message  # Attachment in correct format
        ]
      }
    ]

    # Log the messages as input
    vision_span.set_attribute("braintrust.input_json", JSON.generate(messages))

    # Simulate output
    output = [
      {
        role: "assistant",
        content: "This is a test image showing a simple geometric shape."
      }
    ]

    vision_span.set_attribute("braintrust.output_json", JSON.generate(output))

    # Add metadata
    metadata = {
      model: "vision-model",
      provider: "custom"
    }

    vision_span.set_attribute("braintrust.metadata", JSON.generate(metadata))

    puts "  Created manual span with attachment"
    puts "  Span name: vision.analyze_image"
    puts "  Input: text + image attachment"
    puts "  Output: assistant response"
  end

  puts "\n✓ All examples completed successfully!"
end

# Print permalink to view this trace in Braintrust
puts "\n🔗 View in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Success! Traces with attachments sent to Braintrust!"
