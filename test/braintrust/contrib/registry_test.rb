# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::RegistryTest < Minitest::Test
  def setup
    # Use anonymous subclass to isolate test state
    registry_class = Class.new(Braintrust::Contrib::Registry)
    @registry = registry_class.instance
  end

  # Mock integration class for testing
  def create_mock_integration(name:, gem_names:, require_paths: nil, available: false)
    integration = Class.new do
      include Braintrust::Contrib::Integration

      class << self
        attr_accessor :_integration_name, :_gem_names, :_require_paths, :_available
      end

      def self.integration_name
        _integration_name
      end

      def self.gem_names
        _gem_names
      end

      def self.require_paths
        _require_paths || _gem_names
      end

      def self.available?
        _available
      end
    end

    integration._integration_name = name
    integration._gem_names = gem_names
    integration._require_paths = require_paths
    integration._available = available
    integration
  end

  def test_register_and_lookup
    integration = create_mock_integration(name: :openai, gem_names: ["openai"])

    @registry.register(integration)

    assert_equal integration, @registry[:openai]
    assert_equal integration, @registry["openai"]
  end

  def test_lookup_returns_nil_for_unregistered
    assert_nil @registry[:unknown]
  end

  def test_all_returns_all_integrations
    openai = create_mock_integration(name: :openai, gem_names: ["openai"])
    anthropic = create_mock_integration(name: :anthropic, gem_names: ["anthropic"])

    @registry.register(openai)
    @registry.register(anthropic)

    all = @registry.all
    assert_equal 2, all.length
    assert_includes all, openai
    assert_includes all, anthropic
  end

  def test_available_filters_by_availability
    available_integration = create_mock_integration(
      name: :available,
      gem_names: ["available-gem"],
      available: true
    )
    unavailable_integration = create_mock_integration(
      name: :unavailable,
      gem_names: ["unavailable-gem"],
      available: false
    )

    @registry.register(available_integration)
    @registry.register(unavailable_integration)

    available = @registry.available
    assert_equal 1, available.length
    assert_includes available, available_integration
    refute_includes available, unavailable_integration
  end

  def test_each_iterates_over_integrations
    openai = create_mock_integration(name: :openai, gem_names: ["openai"])
    anthropic = create_mock_integration(name: :anthropic, gem_names: ["anthropic"])

    @registry.register(openai)
    @registry.register(anthropic)

    collected = []
    @registry.each { |i| collected << i }

    assert_equal 2, collected.length
    assert_includes collected, openai
    assert_includes collected, anthropic
  end

  def test_integrations_for_require_path
    openai = create_mock_integration(
      name: :openai,
      gem_names: ["openai"],
      require_paths: ["openai"]
    )
    ruby_openai = create_mock_integration(
      name: :ruby_openai,
      gem_names: ["ruby-openai"],
      require_paths: ["openai"]
    )

    @registry.register(openai)
    @registry.register(ruby_openai)

    integrations = @registry.integrations_for_require_path("openai")
    assert_equal 2, integrations.length
    assert_includes integrations, openai
    assert_includes integrations, ruby_openai
  end

  def test_integrations_for_require_path_strips_rb_extension
    openai = create_mock_integration(
      name: :openai,
      gem_names: ["openai"],
      require_paths: ["openai"]
    )

    @registry.register(openai)

    integrations = @registry.integrations_for_require_path("openai.rb")
    assert_equal 1, integrations.length
    assert_includes integrations, openai
  end

  def test_integrations_for_require_path_returns_empty_for_unknown
    integrations = @registry.integrations_for_require_path("unknown")
    assert_equal [], integrations
    assert integrations.frozen?
  end

  def test_integrations_for_require_path_caching
    openai = create_mock_integration(
      name: :openai,
      gem_names: ["openai"],
      require_paths: ["openai"]
    )

    @registry.register(openai)

    # First call builds the cache
    result1 = @registry.integrations_for_require_path("openai")

    # Second call should return the same frozen array (cached)
    result2 = @registry.integrations_for_require_path("openai")

    assert_same result1, result2
  end

  def test_register_invalidates_cache
    openai = create_mock_integration(
      name: :openai,
      gem_names: ["openai"],
      require_paths: ["openai"]
    )

    @registry.register(openai)

    # Build the cache
    result1 = @registry.integrations_for_require_path("openai")
    assert_equal 1, result1.length

    # Register another integration
    another = create_mock_integration(
      name: :another,
      gem_names: ["another"],
      require_paths: ["openai"]
    )
    @registry.register(another)

    # Cache should be invalidated
    result2 = @registry.integrations_for_require_path("openai")
    assert_equal 2, result2.length
  end

  def test_thread_safety_for_registration
    integrations = 100.times.map do |i|
      create_mock_integration(name: :"integration_#{i}", gem_names: ["gem_#{i}"])
    end

    threads = integrations.map do |integration|
      Thread.new { @registry.register(integration) }
    end

    threads.each(&:join)

    assert_equal 100, @registry.all.length
  end

  def test_thread_safety_for_require_path_lookup
    openai = create_mock_integration(
      name: :openai,
      gem_names: ["openai"],
      require_paths: ["openai"]
    )

    @registry.register(openai)

    errors = []
    threads = 100.times.map do
      Thread.new do
        result = @registry.integrations_for_require_path("openai")
        errors << "Got nil" if result.nil?
        errors << "Wrong length: #{result.length}" unless result.length == 1
      rescue => e
        errors << e.message
      end
    end

    threads.each(&:join)

    assert_equal [], errors
  end
end
