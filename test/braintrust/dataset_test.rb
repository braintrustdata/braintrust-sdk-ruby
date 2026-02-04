# frozen_string_literal: true

require "test_helper"
require "braintrust/dataset"

class Braintrust::DatasetTest < Minitest::Test
  # ============================================
  # Initialization tests
  # ============================================

  def test_initialize_with_name_and_project
    api = mock_api
    dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project", api: api)

    assert_equal "my-dataset", dataset.name
    assert_equal "my-project", dataset.project
  end

  def test_initialize_with_id
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    assert_equal "dataset-123", dataset.id
  end

  def test_initialize_requires_name_or_id
    api = mock_api
    error = assert_raises(ArgumentError) do
      Braintrust::Dataset.new(api: api)
    end

    assert_match(/must specify either :name or :id/, error.message)
  end

  def test_initialize_requires_project_when_using_name
    api = mock_api
    error = assert_raises(ArgumentError) do
      Braintrust::Dataset.new(name: "my-dataset", api: api)
    end

    assert_match(/:project is required when using :name/, error.message)
  end

  def test_initialize_with_version
    api = mock_api
    dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project", version: "1.0", api: api)

    assert_equal "1.0", dataset.version
  end

  def test_initialize_defaults_api_from_global_state
    # Set up global state
    state = get_unit_test_state
    Braintrust::State.global = state

    dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project")

    assert_equal "my-dataset", dataset.name
  ensure
    Braintrust::State.global = nil
  end

  # ============================================
  # ID resolution tests
  # ============================================

  def test_id_returns_provided_id_directly
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    # Should return ID without making API calls
    assert_equal "dataset-123", dataset.id
  end

  # ============================================
  # Enumerable tests
  # ============================================

  def test_dataset_is_enumerable
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    assert dataset.respond_to?(:each)
    assert dataset.respond_to?(:map)
    assert dataset.respond_to?(:select)
    assert dataset.respond_to?(:take)
  end

  # ============================================
  # Origin generation tests
  # ============================================

  def test_build_origin_creates_valid_json
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    raw_record = {
      "id" => "record-456",
      "_xact_id" => "1000196022104685824",
      "dataset_id" => "dataset-123",
      "created" => "2025-10-24T15:29:18.118Z",
      "input" => "test"
    }

    origin = dataset.send(:build_origin, raw_record, "dataset-123")

    assert origin
    parsed = JSON.parse(origin)
    assert_equal "dataset", parsed["object_type"]
    assert_equal "dataset-123", parsed["object_id"]
    assert_equal "record-456", parsed["id"]
    assert_equal "1000196022104685824", parsed["_xact_id"]
  end

  def test_build_origin_uses_fallback_dataset_id
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    raw_record = {
      "id" => "record-456",
      "_xact_id" => "1000196022104685824"
      # No dataset_id in record
    }

    origin = dataset.send(:build_origin, raw_record, "fallback-id")

    parsed = JSON.parse(origin)
    assert_equal "fallback-id", parsed["object_id"]
  end

  def test_build_origin_returns_nil_when_missing_required_fields
    api = mock_api
    dataset = Braintrust::Dataset.new(id: "dataset-123", api: api)

    # Missing id
    record_no_id = {"_xact_id" => "123"}
    assert_nil dataset.send(:build_origin, record_no_id, "dataset-id")

    # Missing _xact_id
    record_no_xact = {"id" => "record-123"}
    assert_nil dataset.send(:build_origin, record_no_xact, "dataset-id")
  end

  # ============================================
  # Integration tests with VCR
  # ============================================

  def test_fetch_all_returns_records_with_origin
    VCR.use_cassette("dataset/fetch_all") do
      state = get_integration_test_state
      api = Braintrust::API.new(state: state)

      # Create/reuse test dataset
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-fetch"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name
      )
      dataset_id = result["dataset"]["id"]

      # Insert test record
      api.datasets.insert(
        id: dataset_id,
        events: [{input: "fetch-test", expected: "FETCH-TEST"}]
      )

      # Use Dataset class to fetch
      dataset = Braintrust::Dataset.new(name: dataset_name, project: project_name, api: api)
      records = dataset.fetch_all(limit: 1)

      assert records.any?, "Expected at least one record"

      record = records.first
      assert record[:input], "Record should have input"
      assert record[:origin], "Record should have origin"

      # Verify origin structure
      origin = JSON.parse(record[:origin])
      assert_equal "dataset", origin["object_type"]
    end
  end

  def test_each_iterates_lazily
    VCR.use_cassette("dataset/each_lazy") do
      state = get_integration_test_state
      api = Braintrust::API.new(state: state)

      # Create/reuse test dataset
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-lazy"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name
      )
      dataset_id = result["dataset"]["id"]

      # Insert test records
      api.datasets.insert(
        id: dataset_id,
        events: [
          {input: "lazy-1", expected: "LAZY-1"},
          {input: "lazy-2", expected: "LAZY-2"}
        ]
      )

      # Use take to only fetch what we need
      dataset = Braintrust::Dataset.new(name: dataset_name, project: project_name, api: api)
      first_record = dataset.take(1).first

      assert first_record, "Expected to get first record"
      assert first_record[:input], "Record should have input"
    end
  end

  private

  def mock_api
    # Create a minimal mock API that won't make real calls
    Minitest::Mock.new
  end
end
