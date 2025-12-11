# frozen_string_literal: true

require "test_helper"

class Braintrust::API::ExperimentsTest < Minitest::Test
  # Note: These tests require recorded VCR cassettes with valid experiment IDs.
  # The experiments endpoint is exercised during the eval_test.rb integration tests.
  # These unit tests are placeholders for future direct API testing.

  def test_comparison_method_exists
    # Test that the comparison method exists with correct signature
    # This is a simple unit test that doesn't require API access
    api = Braintrust::API
    experiments_class = api::Experiments

    assert experiments_class.instance_methods.include?(:comparison)
  end

  def test_experiments_accessor_on_api
    skip "Requires API key" unless ENV["BRAINTRUST_API_KEY"]

    # Test that the experiments accessor returns an Experiments instance
    VCR.use_cassette("api/init") do
      state = get_integration_test_state(enable_tracing: false)
      api = Braintrust::API.new(state: state)

      assert_instance_of Braintrust::API::Experiments, api.experiments
    end
  end
end
