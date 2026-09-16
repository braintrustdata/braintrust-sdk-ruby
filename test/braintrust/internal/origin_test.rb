# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/origin"

class Braintrust::Internal::OriginTest < Minitest::Test
  def test_build_includes_all_fields
    origin = Braintrust::Internal::Origin.build(
      object_type: "dataset",
      object_id: "dataset-123",
      id: "record-456",
      xact_id: "1000196022104685824",
      created: "2025-10-24T15:29:18.118Z"
    )

    assert_equal "dataset", origin["object_type"]
    assert_equal "dataset-123", origin["object_id"]
    assert_equal "record-456", origin["id"]
    assert_equal "1000196022104685824", origin["_xact_id"]
    assert_equal "2025-10-24T15:29:18.118Z", origin["created"]
  end

  def test_build_handles_nil_created
    origin = Braintrust::Internal::Origin.build(
      object_type: "dataset",
      object_id: "dataset-123",
      id: "record-456",
      xact_id: "1000196022104685824",
      created: nil
    )

    assert_nil origin["created"]
    assert_equal "record-456", origin["id"]
  end

  # Pointers we build must be shaped like the ones the Playground sends, so both
  # sources flow through the SDK identically.
  def test_build_uses_string_keys_matching_the_wire_format
    origin = Braintrust::Internal::Origin.build(
      object_type: "dataset",
      object_id: "abc-123",
      id: "def-456",
      xact_id: "789",
      created: "2025-01-01T00:00:00Z"
    )

    assert_instance_of Hash, origin
    assert_equal %w[object_type object_id id _xact_id created].sort, origin.keys.sort
  end

  def test_build_with_playground_logs_type
    origin = Braintrust::Internal::Origin.build(
      object_type: "playground_logs",
      object_id: "playground-123",
      id: "log-456",
      xact_id: "789",
      created: "2025-01-01T00:00:00Z"
    )

    assert_equal "playground_logs", origin["object_type"]
  end
end
