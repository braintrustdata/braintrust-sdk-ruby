# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::SpanCustomizerTest < Minitest::Test
  SUCCESS = OpenTelemetry::SDK::Trace::Export::SUCCESS
  FAILURE = OpenTelemetry::SDK::Trace::Export::FAILURE
  ENDPOINT = "https://api.ruby-sdk-fixture.com/otel/v1/traces"

  def setup
    @requests = []
    @providers = []
    @exporters = []
    stub_request(:post, ENDPOINT).to_return do |request|
      body = (request.headers["Content-Encoding"] == "gzip") ? Zlib.gunzip(request.body) : request.body
      decoded = Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.decode(body)
      @requests << {headers: request.headers, resource_spans: decoded.resource_spans.size, spans: decoded.resource_spans.flat_map { |resource| resource.scope_spans.flat_map { |scope| scope.spans.to_a } }}
      {status: 200, body: ""}
    end
  end

  def teardown
    @providers.each(&:shutdown)
    @exporters.each(&:shutdown)
  end

  def test_order_replacement_routing_and_snapshot_registration_through_init
    first = customizer do |span|
      origin = JSON.parse(span.attributes.fetch("braintrust.context_json"))
      replacement = span.to_span_data.dup
      replacement.name = "#{origin.fetch("span_origin").fetch("name")}:redacted"
      replacement.attributes = {"braintrust.parent" => "project_name:redacted", "braintrust.input_json" => '"[redacted]"'}
      replacement
    end
    second = customizer do |span|
      span.name += ":second"
      span.attributes["customized"] = true
      span
    end
    customizers = [Object.new, Braintrust::SpanCustomizer.new, first, second]
    provider = make_provider
    state = Braintrust.init(
      api_key: "test-api-key", default_project: "original",
      blocking_login: true, set_global: false, auto_instrument: false,
      tracer_provider: provider, span_customizers: customizers
    )
    customizers.clear
    assert_raises(FrozenError) { state.config.span_customizers.clear }
    provider.tracer("manual").start_span("private", attributes: {"braintrust.input_json" => '"secret"'}).finish
    provider.force_flush

    assert_equal 1, @requests.size
    request = @requests.fetch(0)
    assert_equal "project_name:redacted", request[:headers]["X-Bt-Parent"]
    assert_equal "Bearer test-api-key", request[:headers]["Authorization"]
    span = request[:spans].fetch(0)
    assert_equal "braintrust.sdk.ruby:redacted:second", span.name
    assert_equal '"[redacted]"', attributes(span).fetch("braintrust.input_json").string_value
    assert attributes(span).fetch("customized").bool_value
    refute attributes(span).key?("braintrust.context_json"), "replacement must not implicitly merge removed fields"
  end

  def test_attribute_replacement_does_not_mutate_application_or_other_exporters
    provider = make_provider
    memory = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(memory))
    input = +"private"
    source_span = provider.tracer("app").start_span("original", attributes: {"input" => [input]})
    source_span.add_event("event", attributes: {"value" => +"private"})
    source_span.finish
    source = memory.finished_spans.fetch(0)
    hook = customizer do |span|
      span.name = "redacted"
      span.attributes["input"] = ["redacted"]
      span.attributes["added"] = true
      span
    end

    assert_equal SUCCESS, make_exporter([hook]).export([source_span.to_span_data])
    exported = @requests.fetch(0)[:spans].fetch(0)
    assert_equal "redacted", exported.name
    assert_equal "redacted", attributes(exported).fetch("input").array_value.values.fetch(0).string_value
    assert attributes(exported).fetch("added").bool_value
    assert_equal "private", input
    assert_equal "original", source.name
    assert_equal ["private"], source.attributes.fetch("input")
    assert_equal "private", source.events.fetch(0).attributes.fetch("value")
    refute source.attributes.key?("braintrust.context_json")
    assert_equal source.trace_id, exported.trace_id
    assert_equal source.span_id, exported.span_id
  end

  def test_exception_after_mutation_sends_none_of_batch
    spans = two_destinations
    hook = customizer do |span|
      if span.name == "second"
        span.attributes.fetch("input").replace("changed")
        raise "redaction failed"
      end
      span
    end

    assert_equal FAILURE, make_exporter([hook]).export(spans)
    assert_empty @requests
    assert_equal "changed", spans.last.attributes.fetch("input")
  end

  def test_nil_and_non_span_returns_fail_whole_batch
    [nil, {}].each do |invalid|
      hook = customizer { |span| (span.name == "second") ? invalid : span }
      assert_equal FAILURE, make_exporter([hook]).export(two_destinations)
      assert_empty @requests
    end
  end

  def test_unserializable_replacement_fails_before_first_destination_is_sent
    hook = customizer do |span|
      span.start_timestamp = "invalid" if span.name == "second"
      span
    end

    assert_equal FAILURE, make_exporter([hook]).export(two_destinations)
    assert_empty @requests
  end

  def test_identity_is_read_only_while_attributes_are_writable
    source = make_span("original")
    test = self
    hook = customizer do |span|
      [:trace_id, :span_id, :parent_span_id].each do |field|
        test.assert_raises(NoMethodError) { span.public_send("#{field}=", "changed") }
        test.assert_raises(FrozenError) { span.public_send(field).replace("changed") }
      end
      test.assert_raises(NoMethodError) { span[:trace_id] = "changed" }
      span.attributes["input"] = "redacted"
      span
    end

    assert_equal SUCCESS, make_exporter([hook]).export([source])
    exported = @requests.fetch(0)[:spans].fetch(0)
    assert_equal source.trace_id, exported.trace_id
    assert_equal source.span_id, exported.span_id
    assert_equal "redacted", attributes(exported).fetch("input").string_value
  end

  def test_each_hook_must_preserve_all_ids_even_if_later_hook_would_restore_them
    [:trace_id, :span_id, :parent_span_id].each do |field|
      spans = two_destinations
      original = spans.last.public_send(field).dup
      later_called = false
      mutate = customizer do |span|
        if span.name == "second"
          replacement = span.to_span_data.dup
          replacement.public_send("#{field}=", "x" * original.bytesize)
          replacement
        else
          span
        end
      end
      restore = customizer do |span|
        if span.name == "second"
          later_called = true
          span.public_send("#{field}=", original)
        end
        span
      end

      assert_equal FAILURE, make_exporter([mutate, restore]).export(spans)
      assert_empty @requests
      refute later_called
      assert_equal original, spans.last.public_send(field)
    end
  end

  def test_parent_identity_survives_successful_replacement
    provider = make_provider
    tracer = provider.tracer("app")
    parent = tracer.start_span("parent")
    context = OpenTelemetry::Trace.context_with_span(parent)
    child = tracer.start_span("child", with_parent: context)
    child.finish
    parent.finish
    source = child.to_span_data
    hook = customizer do |span|
      replacement = span.to_span_data.dup
      replacement.name = "replacement"
      replacement
    end

    assert_equal SUCCESS, make_exporter([hook]).export([source])
    exported = @requests.fetch(0)[:spans].fetch(0)
    assert_equal source.trace_id, exported.trace_id
    assert_equal source.span_id, exported.span_id
    assert_equal parent.context.span_id, exported.parent_span_id
  end

  def test_resubmission_reruns_customizers_on_current_span_data
    calls = 0
    hook = customizer do |span|
      calls += 1
      span.name += ":customized"
      span
    end
    customizers = [hook]
    exporter = make_exporter(customizers)
    customizers.clear
    source = make_span("original")

    2.times { assert_equal SUCCESS, exporter.export([source]) }
    assert_equal 2, calls
    assert_equal ["original:customized", "original:customized:customized"], @requests.map { |request| request[:spans].fetch(0).name }
    assert_equal "original:customized:customized", source.name
  end

  def test_batch_from_one_resource_shares_one_resource_spans_entry
    tracer = make_provider.tracer("app")
    spans = 3.times.map do |i|
      tracer.start_span("span#{i}", attributes: {"braintrust.parent" => "project_name:original"}).tap(&:finish).to_span_data
    end

    assert_equal SUCCESS, make_exporter([customizer { |span| span }]).export(spans)
    assert_equal 1, @requests.fetch(0)[:resource_spans]
    assert_equal 3, @requests.fetch(0)[:spans].size
  end

  def test_non_standard_errors_from_hooks_fail_closed
    [NotImplementedError, SystemStackError].each do |error|
      hook = customizer { |_span| raise error }
      assert_equal FAILURE, make_exporter([hook]).export(two_destinations)
      assert_empty @requests
    end
  end

  def test_spans_created_by_hooks_are_not_traced
    memory = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    hook_provider = make_provider
    hook_provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(memory))
    hook = customizer do |span|
      hook_provider.tracer("pii-detector").in_span("detect") {}
      span
    end

    assert_equal SUCCESS, make_exporter([hook]).export([make_span("original")])
    assert_empty memory.finished_spans
  end

  def test_later_hook_can_write_attributes_of_replacement_with_frozen_hash
    replace = customizer do |span|
      replacement = span.to_span_data.dup
      replacement.attributes = span.attributes.dup.freeze
      replacement
    end
    write = customizer do |span|
      span.attributes["customized"] = true
      span
    end

    assert_equal SUCCESS, make_exporter([replace, write]).export([make_span("original")])
    assert attributes(@requests.fetch(0)[:spans].fetch(0)).fetch("customized").bool_value
  end

  def test_deleted_entries_are_not_reported_as_dropped
    tracer = make_provider(span_limits: OpenTelemetry::SDK::Trace::SpanLimits.new(event_count_limit: 2)).tracer("app")
    span = tracer.start_span("original", attributes: {"braintrust.parent" => "project_name:original", "secret" => "x"})
    3.times { |i| span.add_event("event#{i}") }
    span.finish
    hook = customizer do |view|
      view.attributes.delete("secret")
      view.events = view.events.first(1)
      view
    end

    assert_equal SUCCESS, make_exporter([hook]).export([span.to_span_data])
    exported = @requests.fetch(0)[:spans].fetch(0)
    assert_equal 0, exported.dropped_attributes_count
    assert_equal 1, exported.dropped_events_count, "limit drops are preserved, deletions are not counted"
  end

  def test_init_rejects_customizers_with_exporter_override
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-api-key", default_project: "original",
        blocking_login: true, set_global: false, auto_instrument: false,
        tracer_provider: make_provider, span_customizers: [customizer { |span| span }],
        exporter: OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
      )
    end
    assert_match(/span_customizers/, error.message)
  end

  private

  def customizer(&block)
    Object.new.tap { |object| object.define_singleton_method(:on_span_export, &block) }
  end

  def make_provider(**options)
    OpenTelemetry::SDK::Trace::TracerProvider.new(**options).tap { |provider| @providers << provider }
  end

  def make_exporter(customizers)
    Braintrust::Trace::SpanExporter.new(endpoint: ENDPOINT, api_key: "test-key", span_customizers: customizers).tap do |exporter|
      @exporters << exporter
    end
  end

  def make_span(name, parent: "project_name:original")
    span = make_provider.tracer("app").start_span(name, attributes: {"braintrust.parent" => parent, "input" => +"private"})
    span.finish
    span.to_span_data
  end

  def two_destinations
    [make_span("first", parent: "project_name:first"), make_span("second", parent: "project_name:second")]
  end

  def attributes(span)
    span.attributes.to_h { |attribute| [attribute.key, attribute.value] }
  end
end
