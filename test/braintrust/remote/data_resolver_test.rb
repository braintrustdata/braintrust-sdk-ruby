# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::DataResolverTest < Minitest::Test
  # ============================================
  # resolve with inline array tests
  # ============================================

  def test_resolve_inline_array
    resolver = Braintrust::Remote::DataResolver.new(mock_api)

    data = [
      {"input" => "hello", "expected" => "HELLO"},
      {"input" => "world", "expected" => "WORLD"}
    ]

    result = resolver.resolve(data)

    assert_equal 2, result.length
    assert_instance_of Braintrust::Remote::EvalCase, result[0]
    assert_equal "hello", result[0].input
    assert_equal "HELLO", result[0].expected
  end

  def test_resolve_nil_returns_nil
    resolver = Braintrust::Remote::DataResolver.new(mock_api)

    result = resolver.resolve(nil)

    assert_nil result
  end

  # ============================================
  # resolve with nested inline data tests
  # ============================================

  def test_resolve_nested_inline_data
    resolver = Braintrust::Remote::DataResolver.new(mock_api)

    data = {
      "data" => [
        {"input" => "a", "expected" => "A"},
        {"input" => "b", "expected" => "B"}
      ]
    }

    result = resolver.resolve(data)

    assert_equal 2, result.length
    assert_equal "a", result[0].input
    assert_equal "b", result[1].input
  end

  # ============================================
  # resolve with dataset_id tests
  # ============================================

  def test_resolve_dataset_by_id
    api = mock_api_with_dataset_fetch([
      {"input" => "fetched1", "expected" => "FETCHED1"},
      {"input" => "fetched2", "expected" => "FETCHED2"}
    ])

    resolver = Braintrust::Remote::DataResolver.new(api)

    data = {"dataset_id" => "ds-123"}
    result = resolver.resolve(data)

    assert_equal 2, result.length
    assert_equal "fetched1", result[0].input
  end

  # ============================================
  # resolve with project_name/dataset_name tests
  # ============================================

  def test_resolve_dataset_by_name
    api = mock_api_with_dataset_lookup("ds-456", [
      {"input" => "named1", "expected" => "NAMED1"}
    ])

    resolver = Braintrust::Remote::DataResolver.new(api)

    data = {"project_name" => "my-project", "dataset_name" => "my-dataset"}
    result = resolver.resolve(data)

    assert_equal 1, result.length
    assert_equal "named1", result[0].input
  end

  # ============================================
  # resolve error cases
  # ============================================

  def test_resolve_invalid_format_raises_error
    resolver = Braintrust::Remote::DataResolver.new(mock_api)

    data = {"unknown_key" => "value"}

    error = assert_raises(ArgumentError) do
      resolver.resolve(data)
    end

    assert_match(/Invalid data format/, error.message)
  end

  # ============================================
  # extract_dataset_id class method tests
  # ============================================

  def test_extract_dataset_id_returns_id
    data = {"dataset_id" => "ds-123"}

    result = Braintrust::Remote::DataResolver.extract_dataset_id(data)

    assert_equal "ds-123", result
  end

  def test_extract_dataset_id_returns_nil_for_inline_data
    data = [{"input" => "a"}]

    result = Braintrust::Remote::DataResolver.extract_dataset_id(data)

    assert_nil result
  end

  def test_extract_dataset_id_returns_nil_for_nested_inline
    data = {"data" => [{"input" => "a"}]}

    result = Braintrust::Remote::DataResolver.extract_dataset_id(data)

    assert_nil result
  end

  def test_extract_dataset_id_returns_nil_for_nil
    result = Braintrust::Remote::DataResolver.extract_dataset_id(nil)

    assert_nil result
  end

  private

  def mock_api
    Object.new
  end

  def mock_api_with_dataset_fetch(rows)
    api = Object.new
    datasets = Object.new

    datasets.define_singleton_method(:fetch_rows) do |id:|
      rows
    end

    api.define_singleton_method(:datasets) { datasets }
    api
  end

  def mock_api_with_dataset_lookup(dataset_id, rows)
    api = Object.new
    datasets = Object.new

    datasets.define_singleton_method(:get) do |project_name:, name:|
      {"id" => dataset_id}
    end

    datasets.define_singleton_method(:fetch_rows) do |id:|
      rows
    end

    api.define_singleton_method(:datasets) { datasets }
    api
  end
end
