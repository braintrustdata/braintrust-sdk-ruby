# frozen_string_literal: true

require "test_helper"

class Braintrust::API::DatasetsTest < Minitest::Test
  def setup
    flunk "BRAINTRUST_API_KEY not set" unless ENV["BRAINTRUST_API_KEY"]

    @state = Braintrust.init(set_global: false, blocking_login: true)
    @api = Braintrust::API.new(state: @state)
    @project_name = "ruby-sdk-test"
  end

  def test_datasets_list_with_project_name
    result = @api.datasets.list(project_name: @project_name)

    assert_instance_of Hash, result
    assert result.key?("objects")
    assert_instance_of Array, result["objects"]
  end

  def test_datasets_create_new_dataset
    dataset_name = unique_name("create")

    response = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name,
      description: "Test dataset for create"
    )

    assert_instance_of Hash, response
    assert response.key?("dataset")
    assert_equal dataset_name, response["dataset"]["name"]
  end

  def test_datasets_create_is_idempotent
    dataset_name = unique_name("idempotent")

    # Create first time
    response1 = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )

    # First call should create a new dataset (found_existing should be false or nil)
    refute response1["found_existing"], "First call should create new dataset"

    # Create again with same name
    response2 = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )

    # Should return the same dataset ID and indicate it already existed
    assert_equal response1["dataset"]["id"], response2["dataset"]["id"]
    assert response2["found_existing"], "Second call should return existing dataset with found_existing=true"
  end

  def test_datasets_get_by_project_and_name
    dataset_name = unique_name("get")

    # Create dataset first
    @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )

    # Fetch it by name
    metadata = @api.datasets.get(project_name: @project_name, name: dataset_name)

    assert_instance_of Hash, metadata
    assert_equal dataset_name, metadata["name"]
    assert metadata.key?("id")
  end

  def test_datasets_get_raises_when_not_found
    error = assert_raises(Braintrust::Error) do
      @api.datasets.get(project_name: @project_name, name: "nonexistent-dataset-xyz")
    end

    assert_match(/not found/, error.message)
  end

  def test_datasets_get_by_id
    dataset_name = unique_name("get-by-id")

    # Create dataset first
    response = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )
    dataset_id = response["dataset"]["id"]

    # Fetch by ID
    metadata = @api.datasets.get_by_id(id: dataset_id)

    assert_instance_of Hash, metadata
    assert_equal dataset_id, metadata["id"]
    assert_equal dataset_name, metadata["name"]
  end

  def test_datasets_insert_events
    dataset_name = unique_name("insert")

    # Create dataset
    response = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )
    dataset_id = response["dataset"]["id"]

    # Insert records
    events = [
      {input: "hello", expected: "HELLO"},
      {input: "world", expected: "WORLD"}
    ]

    insert_response = @api.datasets.insert(id: dataset_id, events: events)

    assert_instance_of Hash, insert_response
    # API may return row_ids or other confirmation
  end

  def test_datasets_fetch_returns_records
    dataset_name = unique_name("fetch")

    # Create dataset and insert records
    response = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )
    dataset_id = response["dataset"]["id"]

    events = [
      {input: "test1", expected: "TEST1"},
      {input: "test2", expected: "TEST2"}
    ]
    @api.datasets.insert(id: dataset_id, events: events)

    # Fetch records
    result = @api.datasets.fetch(id: dataset_id)

    assert_instance_of Hash, result
    assert result.key?(:records)
    assert_instance_of Array, result[:records]

    # Should have at least our 2 records
    assert result[:records].length >= 2
  end

  def test_datasets_fetch_with_pagination
    dataset_name = unique_name("pagination")

    # Create dataset with multiple records
    response = @api.datasets.create(
      project_name: @project_name,
      name: dataset_name
    )
    dataset_id = response["dataset"]["id"]

    # Insert 5 records
    events = 5.times.map { |i| {input: "test#{i}", expected: "TEST#{i}"} }
    @api.datasets.insert(id: dataset_id, events: events)

    # Fetch with small limit to test pagination
    result1 = @api.datasets.fetch(id: dataset_id, limit: 2)

    assert_equal 2, result1[:records].length

    # If there's a cursor, fetch next page
    if result1[:cursor]
      result2 = @api.datasets.fetch(id: dataset_id, limit: 2, cursor: result1[:cursor])
      assert_instance_of Array, result2[:records]
    end
  end
end
