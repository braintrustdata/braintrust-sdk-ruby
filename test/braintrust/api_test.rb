# frozen_string_literal: true

require "test_helper"

class Braintrust::APITest < Minitest::Test
  def setup
  end

  def test_api_new_with_explicit_state
    VCR.use_cassette("api/new_explicit_state") do
      state = get_integration_test_state

      api = Braintrust::API.new(state: state)
      assert_equal state, api.state
    end
  end

  def test_api_new_uses_global_state
    VCR.use_cassette("api/new_global_state") do
      state = Braintrust.init(api_key: get_braintrust_key, set_global: true, blocking_login: true)

      api = Braintrust::API.new
      assert_equal state, api.state
    end
  end

  def test_api_new_raises_without_state
    # Clear global state temporarily
    original_state = Braintrust::State.global
    Braintrust::State.global = nil

    error = assert_raises(Braintrust::Error) do
      Braintrust::API.new
    end
    assert_match(/No state available/, error.message)
  ensure
    # Restore global state
    Braintrust::State.global = original_state
  end

  def test_api_datasets_returns_datasets_instance
    VCR.use_cassette("api/datasets_instance") do
      state = get_integration_test_state
      api = Braintrust::API.new(state: state)

      datasets = api.datasets
      assert_instance_of Braintrust::API::Datasets, datasets
    end
  end

  def test_api_datasets_is_memoized
    VCR.use_cassette("api/datasets_memoized") do
      state = get_integration_test_state
      api = Braintrust::API.new(state: state)

      datasets1 = api.datasets
      datasets2 = api.datasets
      assert_same datasets1, datasets2
    end
  end
end
