# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/openai/deprecated"

class Braintrust::Contrib::OpenAI::DeprecatedTest < Minitest::Test
  def test_wrap_delegates_to_instrument
    mock_client = Object.new
    mock_tracer = Object.new

    captured_args = nil
    Braintrust.stub(:instrument!, ->(name, **opts) { captured_args = [name, opts] }) do
      suppress_logs { Braintrust::Trace::OpenAI.wrap(mock_client, tracer_provider: mock_tracer) }
    end

    assert_equal :openai, captured_args[0]
    assert_same mock_client, captured_args[1][:target]
    assert_same mock_tracer, captured_args[1][:tracer_provider]
  end

  def test_wrap_logs_deprecation_warning
    mock_client = Object.new

    warning_message = nil
    Braintrust.stub(:instrument!, ->(*) {}) do
      Braintrust::Log.stub(:warn, ->(msg) { warning_message = msg }) do
        Braintrust::Trace::OpenAI.wrap(mock_client)
      end
    end

    assert_match(/deprecated/, warning_message)
    assert_match(/Braintrust\.instrument!/, warning_message)
  end

  def test_wrap_returns_client
    mock_client = Object.new

    Braintrust.stub(:instrument!, ->(*) {}) do
      result = suppress_logs { Braintrust::Trace::OpenAI.wrap(mock_client) }
      assert_same mock_client, result
    end
  end
end
