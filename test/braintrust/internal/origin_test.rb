# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/origin"

class Braintrust::Internal::OriginTest < Minitest::Test
  def test_to_json_serializes_all_fields
    result = Braintrust::Internal::Origin.to_json(
      object_type: "dataset",
      object_id: "dataset-123",
      id: "record-456",
      xact_id: "1000196022104685824",
      created: "2025-10-24T15:29:18.118Z"
    )

    parsed = JSON.parse(result)

    assert_equal "dataset", parsed["object_type"]
    assert_equal "dataset-123", parsed["object_id"]
    assert_equal "record-456", parsed["id"]
    assert_equal "1000196022104685824", parsed["_xact_id"]
    assert_equal "2025-10-24T15:29:18.118Z", parsed["created"]
  end

  def test_to_json_handles_nil_created
    result = Braintrust::Internal::Origin.to_json(
      object_type: "dataset",
      object_id: "dataset-123",
      id: "record-456",
      xact_id: "1000196022104685824",
      created: nil
    )

    parsed = JSON.parse(result)

    assert_equal "dataset", parsed["object_type"]
    assert_equal "dataset-123", parsed["object_id"]
    assert_equal "record-456", parsed["id"]
    assert_equal "1000196022104685824", parsed["_xact_id"]
    assert_nil parsed["created"]
  end

  def test_to_json_returns_valid_json_string
    result = Braintrust::Internal::Origin.to_json(
      object_type: "dataset",
      object_id: "abc-123",
      id: "def-456",
      xact_id: "789",
      created: "2025-01-01T00:00:00Z"
    )

    assert_instance_of String, result
    # Should not raise
    JSON.parse(result)
  end

  def test_to_json_with_playground_logs_type
    result = Braintrust::Internal::Origin.to_json(
      object_type: "playground_logs",
      object_id: "playground-123",
      id: "log-456",
      xact_id: "789",
      created: "2025-01-01T00:00:00Z"
    )

    parsed = JSON.parse(result)
    assert_equal "playground_logs", parsed["object_type"]
  end
end
