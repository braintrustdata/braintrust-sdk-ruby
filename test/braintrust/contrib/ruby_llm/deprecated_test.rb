# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/ruby_llm/deprecated"

class Braintrust::Contrib::RubyLLM::DeprecatedTest < Minitest::Test
  # --- .wrap ---

  def test_wrap_delegates_to_instrument
    mock_chat = Object.new
    mock_tracer = Object.new

    captured_args = nil
    Braintrust.stub(:instrument!, ->(name, **opts) { captured_args = [name, opts] }) do
      suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(mock_chat, tracer_provider: mock_tracer) }
    end

    assert_equal :ruby_llm, captured_args[0]
    assert_same mock_chat, captured_args[1][:target]
    assert_same mock_tracer, captured_args[1][:tracer_provider]
  end

  def test_wrap_with_nil_target_instruments_class
    captured_args = nil
    Braintrust.stub(:instrument!, ->(name, **opts) { captured_args = [name, opts] }) do
      suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap }
    end

    assert_equal :ruby_llm, captured_args[0]
    assert_nil captured_args[1][:target]
  end

  def test_wrap_logs_deprecation_warning
    mock_chat = Object.new

    warning_message = nil
    Braintrust.stub(:instrument!, ->(*) {}) do
      Braintrust::Log.stub(:warn, ->(msg) { warning_message = msg }) do
        Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(mock_chat)
      end
    end

    assert_match(/deprecated/, warning_message)
    assert_match(/Braintrust\.instrument!/, warning_message)
  end

  def test_wrap_returns_chat
    mock_chat = Object.new

    Braintrust.stub(:instrument!, ->(*) {}) do
      result = suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(mock_chat) }
      assert_same mock_chat, result
    end
  end

  # --- .unwrap ---

  def test_unwrap_sets_context_enabled_false
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    mock_chat = Object.new

    suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap(mock_chat) }

    ctx = Braintrust::Contrib::Context.from(mock_chat)
    assert_equal false, ctx[:enabled]
  end

  def test_unwrap_with_nil_target_sets_class_context
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap }

    ctx = Braintrust::Contrib::Context.from(::RubyLLM::Chat)
    assert_equal false, ctx[:enabled]

    # Clean up
    Braintrust::Contrib::Context.set!(::RubyLLM::Chat, enabled: true)
  end

  def test_unwrap_logs_deprecation_warning
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    mock_chat = Object.new

    warning_message = nil
    Braintrust::Log.stub(:warn, ->(msg) { warning_message = msg }) do
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap(mock_chat)
    end

    assert_match(/deprecated/, warning_message)
  end

  def test_unwrap_returns_chat
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    mock_chat = Object.new

    result = suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap(mock_chat) }
    assert_same mock_chat, result
  end

  # --- E2E: unwrap disables instrumentation ---

  def test_unwrap_disables_instrumentation_for_subsequent_requests
    skip "RubyLLM gem not available" unless defined?(::RubyLLM::Chat)

    VCR.use_cassette("contrib/ruby_llm/basic_chat") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")

      # Instrument the chat instance
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)

      # First request should create a span
      chat.ask("Say 'test'")
      spans_before = rig.drain
      assert_equal 1, spans_before.length, "Expected 1 span before unwrap"

      # Now unwrap the chat instance
      suppress_logs { Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap(chat) }

      # Second request should NOT create a span
      chat.ask("Say 'test'")
      spans_after = rig.drain
      assert_equal 0, spans_after.length, "Expected 0 spans after unwrap"
    end
  end
end
