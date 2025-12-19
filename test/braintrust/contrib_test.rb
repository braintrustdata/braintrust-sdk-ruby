# frozen_string_literal: true

require "test_helper"

class Braintrust::ContribTest < Minitest::Test
  # --- Braintrust.instrument! delegation ---

  def test_braintrust_instrument_delegates_to_contrib
    called_with = nil

    Braintrust::Contrib.stub(:instrument!, ->(*args, **kwargs) { called_with = [args, kwargs] }) do
      Braintrust.instrument!(:openai, tracer_provider: "test-provider")
    end

    assert_equal [[:openai], {tracer_provider: "test-provider"}], called_with
  end

  # --- registry ---

  def test_registry_returns_registry_instance
    mock_registry = Object.new

    Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
      assert_same mock_registry, Braintrust::Contrib.registry
    end
  end

  # --- init ---

  def test_init_sets_default_tracer_provider
    mock_provider = Object.new
    original = Braintrust::Contrib.instance_variable_get(:@default_tracer_provider)

    Braintrust::Contrib.init(tracer_provider: mock_provider)
    assert_same mock_provider, Braintrust::Contrib.default_tracer_provider
  ensure
    Braintrust::Contrib.instance_variable_set(:@default_tracer_provider, original)
  end

  # --- instrument! ---

  def test_instrument_delegates_to_integration
    mock_integration = Minitest::Mock.new
    mock_integration.expect(:instrument!, true, [], tracer_provider: "test-provider")

    mock_registry = {test_integration: mock_integration}

    Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
      Braintrust::Contrib.instrument!(:test_integration, tracer_provider: "test-provider")
    end

    mock_integration.verify
  end

  def test_instrument_logs_error_for_unknown_integration
    mock_registry = {}
    logged_error = nil

    Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
      Braintrust::Log.stub(:error, ->(msg) { logged_error = msg }) do
        Braintrust::Contrib.instrument!(:unknown_integration)
      end
    end

    assert_match(/No integration for 'unknown_integration'/, logged_error)
  end

  def test_instrument_passes_target_option
    mock_integration = Minitest::Mock.new
    target = Object.new
    mock_integration.expect(:instrument!, true, [], target: target)

    mock_registry = {openai: mock_integration}

    Braintrust::Contrib::Registry.stub(:instance, mock_registry) do
      Braintrust::Contrib.instrument!(:openai, target: target)
    end

    mock_integration.verify
  end

  # --- default_tracer_provider ---

  def test_default_tracer_provider_falls_back_to_opentelemetry
    mock_otel_provider = Object.new
    original = Braintrust::Contrib.instance_variable_get(:@default_tracer_provider)
    Braintrust::Contrib.instance_variable_set(:@default_tracer_provider, nil)

    OpenTelemetry.stub(:tracer_provider, mock_otel_provider) do
      assert_same mock_otel_provider, Braintrust::Contrib.default_tracer_provider
    end
  ensure
    Braintrust::Contrib.instance_variable_set(:@default_tracer_provider, original)
  end

  # --- context_for ---

  def test_context_for_delegates_to_context_from
    target = Object.new
    mock_context = Object.new

    Braintrust::Contrib::Context.stub(:from, ->(t) { (t == target) ? mock_context : nil }) do
      assert_same mock_context, Braintrust::Contrib.context_for(target)
    end
  end

  def test_context_for_returns_nil_when_no_context
    target = Object.new

    Braintrust::Contrib::Context.stub(:from, nil) do
      assert_nil Braintrust::Contrib.context_for(target)
    end
  end

  # --- tracer_provider_for ---

  def test_tracer_provider_for_returns_context_provider_when_present
    target = Object.new
    context_provider = Object.new
    mock_context = Minitest::Mock.new
    mock_context.expect(:[], context_provider, [:tracer_provider])

    Braintrust::Contrib::Context.stub(:from, mock_context) do
      assert_same context_provider, Braintrust::Contrib.tracer_provider_for(target)
    end

    mock_context.verify
  end

  def test_tracer_provider_for_falls_back_to_default_when_no_context
    target = Object.new
    default_provider = Object.new

    Braintrust::Contrib::Context.stub(:from, nil) do
      Braintrust::Contrib.stub(:default_tracer_provider, default_provider) do
        assert_same default_provider, Braintrust::Contrib.tracer_provider_for(target)
      end
    end
  end

  def test_tracer_provider_for_falls_back_when_context_has_no_provider
    target = Object.new
    default_provider = Object.new
    mock_context = Minitest::Mock.new
    mock_context.expect(:[], nil, [:tracer_provider])

    Braintrust::Contrib::Context.stub(:from, mock_context) do
      Braintrust::Contrib.stub(:default_tracer_provider, default_provider) do
        assert_same default_provider, Braintrust::Contrib.tracer_provider_for(target)
      end
    end

    mock_context.verify
  end

  # --- tracer_for ---

  def test_tracer_for_gets_tracer_from_provider
    target = Object.new
    mock_tracer = Object.new
    mock_provider = Minitest::Mock.new
    mock_provider.expect(:tracer, mock_tracer, ["braintrust"])

    Braintrust::Contrib.stub(:tracer_provider_for, mock_provider) do
      assert_same mock_tracer, Braintrust::Contrib.tracer_for(target)
    end

    mock_provider.verify
  end

  def test_tracer_for_uses_custom_name
    target = Object.new
    mock_tracer = Object.new
    mock_provider = Minitest::Mock.new
    mock_provider.expect(:tracer, mock_tracer, ["custom-tracer"])

    Braintrust::Contrib.stub(:tracer_provider_for, mock_provider) do
      assert_same mock_tracer, Braintrust::Contrib.tracer_for(target, name: "custom-tracer")
    end

    mock_provider.verify
  end

  def test_tracer_for_uses_target_context_provider
    target = Object.new
    mock_tracer = Object.new
    context_provider = Minitest::Mock.new
    context_provider.expect(:tracer, mock_tracer, ["braintrust"])

    mock_context = Minitest::Mock.new
    mock_context.expect(:[], context_provider, [:tracer_provider])

    Braintrust::Contrib::Context.stub(:from, mock_context) do
      assert_same mock_tracer, Braintrust::Contrib.tracer_for(target)
    end

    context_provider.verify
    mock_context.verify
  end
end
