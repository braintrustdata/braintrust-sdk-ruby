#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Comprehensive example for RubyLLM integration with Braintrust
#
# This example demonstrates:
# - Basic chat completions with OpenAI and Anthropic
# - Multi-turn conversations
# - Streaming responses
# - Tool calling
# - Different models
# - Direct complete() calls (ActiveRecord pattern)
# - Error handling

# Check for API keys
unless ENV["OPENAI_API_KEY"] && ENV["ANTHROPIC_API_KEY"]
  puts "Error: Both OPENAI_API_KEY and ANTHROPIC_API_KEY environment variables are required"
  puts "Get your OpenAI API key from: https://platform.openai.com/api-keys"
  puts "Get your Anthropic API key from: https://console.anthropic.com/"
  exit 1
end

Braintrust.init(
  default_project: "ruby-sdk-internal-examples",
  blocking_login: true
)

# Instrument all RubyLLM chats with Braintrust tracing
Braintrust.instrument!(:ruby_llm)

# Configure RubyLLM with both providers
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end

# Define tool classes outside the span to avoid StandardRB violations
class WeatherTool < RubyLLM::Tool
  description "Get the current weather for a location"

  params do
    string :location, description: "The city and state, e.g. San Francisco, CA"
    string :unit, description: "Temperature unit (celsius or fahrenheit)"
  end

  def execute(location:, unit: "fahrenheit")
    temp = (unit == "celsius") ? 22 : 72
    {location: location, temperature: temp, unit: unit, conditions: "sunny"}
  end
end

class CalculatorTool < RubyLLM::Tool
  description "Perform basic arithmetic operations"

  params do
    string :operation, description: "The operation to perform (add, subtract, multiply, divide)"
    number :a, description: "First number"
    number :b, description: "Second number"
  end

  def execute(operation:, a:, b:)
    result = case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then (b != 0) ? a / b : "Error: Division by zero"
    end
    {operation: operation, a: a, b: b, result: result}
  end
end

# Create a root span to capture all tests
tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm-integration-test")
root_span = nil

puts "Running comprehensive RubyLLM integration tests..."
puts "Testing features across OpenAI and Anthropic providers"

tracer.in_span("examples/internal/contrib/ruby_llm/golden.rb") do |span|
  root_span = span

  # Feature 1: Basic Chat
  puts "\n" + "=" * 80
  puts "Feature 1: Basic Chat"
  puts "=" * 80

  tracer.in_span("feature_basic_chat") do
    puts "\n[OpenAI - gpt-4o-mini]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    response = chat_openai.ask("What is Ruby?")
    puts "Q: What is Ruby?"
    puts "A: #{response.content[0..150]}..."
    puts "Tokens: #{response.to_h[:input_tokens]} in, #{response.to_h[:output_tokens]} out"

    puts "\n[Anthropic - claude-sonnet-4]"
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")
    response = chat_anthropic.ask("What is Claude?")
    puts "Q: What is Claude?"
    puts "A: #{response.content[0..150]}..."
    puts "Tokens: #{response.to_h[:input_tokens]} in, #{response.to_h[:output_tokens]} out"
  end

  # Feature 2: Multi-turn Conversation
  puts "\n" + "=" * 80
  puts "Feature 2: Multi-turn Conversation"
  puts "=" * 80

  tracer.in_span("feature_multi_turn_conversation") do
    puts "\n[OpenAI - gpt-4o-mini]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    chat_openai.ask("What is Ruby programming language?")
    response = chat_openai.ask("Who created it?")
    puts "Turn 1: What is Ruby programming language?"
    puts "Turn 2: Who created it?"
    puts "A: #{response.content[0..150]}..."
    puts "History: #{chat_openai.messages.length} messages"

    puts "\n[Anthropic - claude-sonnet-4]"
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")
    chat_anthropic.ask("What is Claude?")
    response = chat_anthropic.ask("Who created you?")
    puts "Turn 1: What is Claude?"
    puts "Turn 2: Who created you?"
    puts "A: #{response.content[0..150]}..."
    puts "History: #{chat_anthropic.messages.length} messages"
  end

  # Feature 3: Streaming
  puts "\n" + "=" * 80
  puts "Feature 3: Streaming Responses"
  puts "=" * 80

  tracer.in_span("feature_streaming") do
    puts "\n[OpenAI - gpt-4o-mini]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    print "Q: Write a haiku about programming\nA (streaming): "
    chat_openai.ask("Write a haiku about programming") do |chunk|
      print chunk.content
    end
    puts

    puts "\n[Anthropic - claude-sonnet-4]"
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")
    print "Q: Write a limerick about AI\nA (streaming): "
    chat_anthropic.ask("Write a limerick about AI") do |chunk|
      print chunk.content
    end
    puts
  end

  # Feature 4: Tool Calling
  puts "\n" + "=" * 80
  puts "Feature 4: Tool Calling"
  puts "=" * 80

  tracer.in_span("feature_tool_calling") do
    puts "\n[OpenAI - gpt-4o-mini with WeatherTool]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    chat_openai.with_tool(WeatherTool)
    response = chat_openai.ask("What's the weather like in San Francisco?")
    puts "Q: What's the weather like in San Francisco?"
    puts "A: #{response.content}"

    puts "\n[Anthropic - claude-sonnet-4 with CalculatorTool]"
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")
    chat_anthropic.with_tool(CalculatorTool)
    response = chat_anthropic.ask("What is 156 multiplied by 47?")
    puts "Q: What is 156 multiplied by 47?"
    puts "A: #{response.content}"
  end

  # Feature 5: Different Models
  puts "\n" + "=" * 80
  puts "Feature 5: Different Models"
  puts "=" * 80

  tracer.in_span("feature_different_models") do
    puts "\n[OpenAI - gpt-4o (larger model)]"
    chat_gpt4 = RubyLLM.chat(model: "gpt-4o")
    response = chat_gpt4.ask("Explain quantum computing in one sentence")
    puts "Model: gpt-4o"
    puts "Q: Explain quantum computing in one sentence"
    puts "A: #{response.content}"

    puts "\n[Mixed Providers - Same Question]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")

    response_openai = chat_openai.ask("What is 2+2?")
    response_anthropic = chat_anthropic.ask("What is 2+2?")
    puts "Q: What is 2+2?"
    puts "OpenAI (gpt-4o-mini): #{response_openai.content}"
    puts "Anthropic (claude-sonnet-4): #{response_anthropic.content}"
  end

  # Feature 6: Direct complete() call (ActiveRecord pattern)
  # This demonstrates how RubyLLM's ActiveRecord integration (acts_as_chat) works:
  # it adds messages directly to chat history and calls complete() instead of ask()
  puts "\n" + "=" * 80
  puts "Feature 6: Direct complete() Call (ActiveRecord Pattern)"
  puts "=" * 80

  tracer.in_span("feature_direct_complete") do
    puts "\n[OpenAI - gpt-4o-mini via complete()]"
    chat_openai = RubyLLM.chat(model: "gpt-4o-mini")
    # Simulate ActiveRecord pattern: add message directly, then call complete()
    chat_openai.add_message(role: :user, content: "Say 'hello from complete()'")
    response = chat_openai.complete
    puts "Pattern: add_message() + complete()"
    puts "A: #{response.content}"
    puts "Tokens: #{response.to_h[:input_tokens]} in, #{response.to_h[:output_tokens]} out"

    puts "\n[Anthropic - claude-sonnet-4 via complete()]"
    chat_anthropic = RubyLLM.chat(model: "claude-sonnet-4")
    chat_anthropic.add_message(role: :user, content: "Say 'hello from complete()'")
    response = chat_anthropic.complete
    puts "Pattern: add_message() + complete()"
    puts "A: #{response.content}"
    puts "Tokens: #{response.to_h[:input_tokens]} in, #{response.to_h[:output_tokens]} out"
  end

  # Feature 7: Error Handling
  puts "\n" + "=" * 80
  puts "Feature 7: Error Handling"
  puts "=" * 80

  tracer.in_span("feature_error_handling") do
    chat_error = RubyLLM.chat(model: "invalid-model")
    chat_error.ask("This should fail")
  rescue => e
    puts "✓ Gracefully caught error: #{e.class.name}"
    puts "  Message: #{e.message}"
  end

  # Feature 8: Image Attachments (Issue #71 fix)
  # This demonstrates proper handling of RubyLLM Content objects with attachments
  puts "\n" + "=" * 80
  puts "Feature 8: Image Attachments"
  puts "=" * 80

  tracer.in_span("feature_image_attachments") do
    require "tempfile"

    # Create a minimal valid PNG image (10x10 red square)
    png_data = [
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x0a,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x02, 0x50, 0x58, 0xea, 0x00, 0x00, 0x00,
      0x12, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xf8, 0xcf, 0xc0, 0x80,
      0x07, 0x31, 0x8c, 0x4a, 0x63, 0x43, 0x00, 0xb7, 0xca, 0x63, 0x9d, 0xd6,
      0xd5, 0xef, 0x74, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82
    ].pack("C*")

    # Create a temp PNG file
    tmpfile = Tempfile.new(["test_image", ".png"])
    tmpfile.binmode
    tmpfile.write(png_data)
    tmpfile.close

    begin
      puts "\n[OpenAI - gpt-4o-mini with Image Attachment]"
      chat_openai = RubyLLM.chat(model: "gpt-4o-mini")

      # Use RubyLLM's Content class with attachment
      # This triggers the Content object behavior (issue #71)
      content = RubyLLM::Content.new("What color is this image? Reply in one word.")
      content.add_attachment(tmpfile.path)

      chat_openai.add_message(role: :user, content: content)
      response = chat_openai.complete

      puts "Q: What color is this image? (with PNG attachment)"
      puts "A: #{response.content}"
      puts "Tokens: #{response.to_h[:input_tokens]} in, #{response.to_h[:output_tokens]} out"
      puts "Note: The trace includes the base64-encoded image attachment"
    ensure
      tmpfile.unlink
    end
  end
end

puts "\n" + "=" * 80
puts "✓ All feature tests completed successfully!"
puts "=" * 80

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
