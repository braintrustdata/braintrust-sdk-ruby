# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"

class Braintrust::Trace::SpanExporterTest < Minitest::Test
  SUCCESS = OpenTelemetry::SDK::Trace::Export::SUCCESS
  FAILURE = OpenTelemetry::SDK::Trace::Export::FAILURE

  def setup
    @state = get_unit_test_state
  end

  # Build a minimal SpanData-like struct for testing
  SpanStub = Struct.new(:name, :attributes, keyword_init: true)

  def make_span(name, parent: nil)
    attrs = {}
    attrs[Braintrust::Trace::SpanProcessor::PARENT_ATTR_KEY] = parent if parent
    SpanStub.new(name: name, attributes: attrs)
  end

  # A test double that records each export call's spans and headers
  # instead of making HTTP requests.
  #
  # Overrides both `encode` (to skip protobuf serialization of span data)
  # and `send_bytes` (to record calls instead of making HTTP requests).
  # The parent OTLP::Exporter#export calls encode then send_bytes,
  # so both must be overridden for stub span data to work.
  class RecordingExporter < Braintrust::Trace::SpanExporter
    attr_reader :calls

    def initialize
      @calls = []
      # Initialize headers directly — skip super to avoid HTTP setup
      @headers = {"Authorization" => "Bearer test-key"}
      @shutdown = false
    end

    private

    # Skip protobuf encoding — return dummy bytes
    def encode(span_data)
      "encoded"
    end

    # Record the export call instead of making HTTP requests
    def send_bytes(data, timeout:)
      @calls << {headers: @headers.dup}
      SUCCESS
    end
  end

  def test_groups_spans_by_parent_attribute
    exporter = RecordingExporter.new

    spans = [
      make_span("span1", parent: "experiment_id:exp-1"),
      make_span("span2", parent: "experiment_id:exp-1"),
      make_span("span3", parent: "project_name:proj-2")
    ]

    result = exporter.export(spans)

    assert_equal SUCCESS, result
    assert_equal 2, exporter.calls.length
  end

  def test_sets_x_bt_parent_header_per_group
    exporter = RecordingExporter.new

    spans = [
      make_span("span1", parent: "experiment_id:exp-1"),
      make_span("span2", parent: "project_name:proj-2")
    ]

    exporter.export(spans)

    headers = exporter.calls.map { |c| c[:headers]["x-bt-parent"] }
    assert_includes headers, "experiment_id:exp-1"
    assert_includes headers, "project_name:proj-2"
  end

  def test_clears_header_after_export
    exporter = RecordingExporter.new

    spans = [make_span("span1", parent: "experiment_id:exp-1")]
    exporter.export(spans)

    # After export completes, header should be cleaned up
    refute exporter.instance_variable_get(:@headers).key?("x-bt-parent")
  end

  def test_handles_nil_parent
    exporter = RecordingExporter.new

    spans = [make_span("span1")]  # no parent attribute
    result = exporter.export(spans)

    assert_equal SUCCESS, result
    assert_equal 1, exporter.calls.length
    refute exporter.calls[0][:headers].key?("x-bt-parent")
  end

  def test_mixed_nil_and_non_nil_parents
    exporter = RecordingExporter.new

    spans = [
      make_span("span1"),  # nil parent
      make_span("span2", parent: "experiment_id:exp-1"),
      make_span("span3")   # nil parent
    ]

    result = exporter.export(spans)

    assert_equal SUCCESS, result
    assert_equal 2, exporter.calls.length

    # Find the call without x-bt-parent (nil group)
    nil_call = exporter.calls.find { |c| !c[:headers].key?("x-bt-parent") }
    assert nil_call, "Expected a call without x-bt-parent header"

    # Find the call with x-bt-parent
    parent_call = exporter.calls.find { |c| c[:headers]["x-bt-parent"] == "experiment_id:exp-1" }
    assert parent_call, "Expected a call with x-bt-parent header"
  end

  def test_returns_failure_when_any_group_fails
    exporter = RecordingExporter.new
    call_count = 0
    # Make the second call fail
    exporter.define_singleton_method(:send_bytes) do |data, timeout:|
      call_count += 1
      (call_count == 2) ? FAILURE : SUCCESS
    end

    spans = [
      make_span("span1", parent: "experiment_id:exp-1"),
      make_span("span2", parent: "project_name:proj-2")
    ]

    result = exporter.export(spans)
    assert_equal FAILURE, result
  end

  def test_returns_success_when_all_groups_succeed
    exporter = RecordingExporter.new

    spans = [
      make_span("span1", parent: "experiment_id:exp-1"),
      make_span("span2", parent: "project_name:proj-2")
    ]

    result = exporter.export(spans)
    assert_equal SUCCESS, result
  end

  def test_empty_span_data
    exporter = RecordingExporter.new

    result = exporter.export([])
    assert_equal SUCCESS, result
    assert_equal 0, exporter.calls.length
  end

  def test_header_cleaned_up_even_on_error
    exporter = RecordingExporter.new
    exporter.define_singleton_method(:send_bytes) do |data, timeout:|
      raise "boom"
    end

    spans = [make_span("span1", parent: "experiment_id:exp-1")]

    assert_raises(RuntimeError) { exporter.export(spans) }

    # Header should be cleaned up despite the exception
    refute exporter.instance_variable_get(:@headers).key?("x-bt-parent")
  end
end
