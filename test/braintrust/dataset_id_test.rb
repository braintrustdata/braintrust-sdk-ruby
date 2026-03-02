# frozen_string_literal: true

require "test_helper"
require "braintrust/dataset"

class Braintrust::DatasetIdTest < Minitest::Test
  def test_stores_id
    dataset_id = Braintrust::DatasetId.new(id: "ds-456")
    assert_equal "ds-456", dataset_id.id
  end

  def test_equality
    a = Braintrust::DatasetId.new(id: "ds-456")
    b = Braintrust::DatasetId.new(id: "ds-456")
    assert_equal a, b
  end
end
