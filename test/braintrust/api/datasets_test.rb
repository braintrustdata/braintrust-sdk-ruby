# frozen_string_literal: true

require "test_helper"

class Braintrust::API::DatasetsTest < Minitest::Test
  def setup
    flunk "BRAINTRUST_API_KEY not set" unless ENV["BRAINTRUST_API_KEY"]
    @project_name = "ruby-sdk-test"
  end

  def get_test_api
    state = Braintrust.init(set_global: false, blocking_login: true)
    Braintrust::API.new(state: state)
  end

  def test_datasets_list_with_project_name
    VCR.use_cassette("datasets/list") do
      api = get_test_api
      result = api.datasets.list(project_name: @project_name)

      assert_instance_of Hash, result
      assert result.key?("objects")
      assert_instance_of Array, result["objects"]
    end
  end

  def test_datasets_create_new_dataset
    VCR.use_cassette("datasets/create") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-create"

      response = api.datasets.create(
        project_name: @project_name,
        name: dataset_name,
        description: "Test dataset for create"
      )

      assert_instance_of Hash, response
      assert response.key?("dataset")
      assert_equal dataset_name, response["dataset"]["name"]
    end
  end

  def test_datasets_create_is_idempotent
    VCR.use_cassette("datasets/create_idempotent") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-idempotent"

      # Call create twice with same name
      response1 = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )

      response2 = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )

      # Both calls should succeed and return the same dataset ID
      assert_instance_of Hash, response1
      assert_instance_of Hash, response2
      assert response1["dataset"]
      assert response2["dataset"]
      assert_equal response1["dataset"]["id"], response2["dataset"]["id"], "Both creates should return same dataset ID"
    end
  end

  def test_datasets_get_by_project_and_name
    VCR.use_cassette("datasets/get_by_name") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-get"

      # Create dataset first
      api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )

      # Fetch it by name
      metadata = api.datasets.get(project_name: @project_name, name: dataset_name)

      assert_instance_of Hash, metadata
      assert_equal dataset_name, metadata["name"]
      assert metadata.key?("id")
    end
  end

  def test_datasets_get_raises_when_not_found
    VCR.use_cassette("datasets/get_not_found") do
      api = get_test_api
      error = assert_raises(Braintrust::Error) do
        api.datasets.get(project_name: @project_name, name: "nonexistent-dataset-xyz")
      end

      assert_match(/not found/, error.message)
    end
  end

  def test_datasets_get_by_id
    VCR.use_cassette("datasets/get_by_id") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-get-by-id"

      # Create dataset first
      response = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )
      dataset_id = response["dataset"]["id"]

      # Fetch by ID
      metadata = api.datasets.get_by_id(id: dataset_id)

      assert_instance_of Hash, metadata
      assert_equal dataset_id, metadata["id"]
      assert_equal dataset_name, metadata["name"]
    end
  end

  def test_datasets_insert_events
    VCR.use_cassette("datasets/insert") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-insert"

      # Create dataset
      response = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )
      dataset_id = response["dataset"]["id"]

      # Insert records
      events = [
        {input: "hello", expected: "HELLO"},
        {input: "world", expected: "WORLD"}
      ]

      insert_response = api.datasets.insert(id: dataset_id, events: events)

      assert_instance_of Hash, insert_response
      # API may return row_ids or other confirmation
    end
  end

  def test_datasets_fetch_returns_records
    VCR.use_cassette("datasets/fetch") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-fetch"

      # Create dataset and insert records
      response = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )
      dataset_id = response["dataset"]["id"]

      events = [
        {input: "test1", expected: "TEST1"},
        {input: "test2", expected: "TEST2"}
      ]
      api.datasets.insert(id: dataset_id, events: events)

      # Fetch records
      result = api.datasets.fetch(id: dataset_id)

      assert_instance_of Hash, result
      assert result.key?(:records)
      assert_instance_of Array, result[:records]

      # Should have at least our 2 records
      assert result[:records].length >= 2
    end
  end

  def test_datasets_fetch_with_pagination
    VCR.use_cassette("datasets/fetch_pagination") do
      api = get_test_api
      dataset_name = "test-ruby-sdk-pagination"

      # Create dataset with multiple records
      response = api.datasets.create(
        project_name: @project_name,
        name: dataset_name
      )
      dataset_id = response["dataset"]["id"]

      # Insert 5 records
      events = 5.times.map { |i| {input: "test#{i}", expected: "TEST#{i}"} }
      api.datasets.insert(id: dataset_id, events: events)

      # Fetch with small limit to test pagination
      result1 = api.datasets.fetch(id: dataset_id, limit: 2)

      assert_equal 2, result1[:records].length

      # If there's a cursor, fetch next page
      if result1[:cursor]
        result2 = api.datasets.fetch(id: dataset_id, limit: 2, cursor: result1[:cursor])
        assert_instance_of Array, result2[:records]
      end
    end
  end
end
