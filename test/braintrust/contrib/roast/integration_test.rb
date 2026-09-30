# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/roast/integration"
require "tmpdir"

class Braintrust::Contrib::Roast::IntegrationTest < Minitest::Test
  def setup
    skip "roast-ai gem not available" unless Gem.loaded_specs["roast-ai"]

    require "roast"
  end

  def test_integration_metadata
    integration = Braintrust::Contrib::Roast::Integration

    assert_equal :roast, integration.integration_name
    assert_equal ["roast-ai"], integration.gem_names
    assert_equal ["roast"], integration.require_paths
    assert_equal "1.0.0", integration.minimum_version
    assert integration.loaded?
  end

  def test_workflow_and_cogs_form_parent_child_spans
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)

    with_workflow("execute do\n  ruby(:first) { 2 }\n  ruby(:second) { 3 }\nend\n") do |path|
      run_workflow(path)
    end

    spans = rig.drain
    assert_equal 3, spans.length
    workflow = spans.find { |span| span.name == "roast.workflow" }
    refute_nil workflow
    workflow_attrs = JSON.parse(workflow.attributes.fetch("braintrust.span_attributes"))
    assert_equal "task", workflow_attrs.fetch("type")
    assert_equal "roast.workflow", workflow_attrs.fetch("name")

    cogs = spans.reject { |span| span == workflow }
    assert_equal ["roast.cog.first", "roast.cog.second"], cogs.map(&:name).sort
    assert_equal cogs.map(&:name).sort, cogs.map { |span| JSON.parse(span.attributes.fetch("braintrust.span_attributes")).fetch("name") }.sort
    assert cogs.all? { |span| span.parent_span_id == [workflow.hex_span_id].pack("H*") }
    assert_equal ["ruby", "ruby"], cogs.map { |span| JSON.parse(span.attributes.fetch("braintrust.metadata")).fetch("cog_type") }
  end

  def test_chat_cog_contains_ruby_llm_request
    require "ruby_llm"
    RubyLLM.configure { |config| config.openai_api_key = get_openai_key }
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)
    assert Braintrust.instrument!(:ruby_llm)

    source = <<~ROAST
      config do
        chat(:answer) { no_show_stats! }
      end
      execute do
        chat(:answer) { "What is the capital of France? Answer in one word." }
      end
    ROAST
    ClimateControl.modify(OPENAI_API_KEY: get_openai_key) do
      VCR.use_cassette("contrib/roast/basic_chat") do
        with_workflow(source) { |path| run_workflow(path) }
      end
    end

    spans = rig.drain
    cog = spans.find { |span| span.name == "roast.cog.answer" }
    llm = spans.find { |span| span.name == "ruby_llm.chat" }
    refute_nil cog
    refute_nil llm
    assert_equal [cog.hex_span_id].pack("H*"), llm.parent_span_id
    assert_equal "Paris", JSON.parse(cog.attributes.fetch("braintrust.output_json"))
  end

  def test_from_file_keeps_enclosing_span_as_workflow_parent
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)

    tracer = rig.tracer_provider.tracer("roast-test")
    with_workflow("execute do\n  ruby(:step) { 1 }\nend\n") do |path|
      tracer.in_span("root") do
        ::Roast::Workflow.from_file(path, ::Roast::WorkflowParams.new([], [], {}))
      end
    end

    spans = rig.drain
    root = spans.find { |span| span.name == "root" }
    workflow = spans.find { |span| span.name == "roast.workflow" }
    assert_equal [root.hex_span_id].pack("H*"), workflow.parent_span_id
  end

  def test_failed_cog_records_error_and_preserves_exception
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)

    with_workflow("execute do\n  ruby(:explode) { raise 'boom' }\nend\n") do |path|
      assert_raises(RuntimeError) do
        run_workflow(path)
      end
    end

    cog = rig.drain.find { |span| span.name == "roast.cog.explode" }
    refute_nil cog
    assert_equal OpenTelemetry::Trace::Status::ERROR, cog.status.code
  end

  def test_parallel_cogs_keep_workflow_parent
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)

    source = <<~ROAST
      config do
        ruby(:first) { async! }
        ruby(:second) { async! }
      end
      execute do
        ruby(:first) { 2 }
        ruby(:second) { 3 }
      end
    ROAST
    with_workflow(source) { |path| run_workflow(path) }

    spans = rig.drain
    workflow = spans.find { |span| span.name == "roast.workflow" }
    cogs = spans.grep_v(workflow)
    assert_equal 2, cogs.length
    assert cogs.all? { |span| span.parent_span_id == [workflow.hex_span_id].pack("H*") }
  end

  def test_nested_scope_cog_is_child_of_call_cog
    rig = setup_otel_test_rig
    Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
    assert Braintrust.instrument!(:roast)

    source = <<~ROAST
      execute(:inner) do
        ruby(:inside) { 42 }
      end
      execute do
        call(:branch, run: :inner) { :value }
      end
    ROAST
    with_workflow(source) { |path| run_workflow(path) }

    spans = rig.drain
    branch = spans.find { |span| span.name == "roast.cog.branch" }
    inside = spans.find { |span| span.name == "roast.cog.inside" }
    refute_nil branch
    refute_nil inside
    assert_equal [branch.hex_span_id].pack("H*"), inside.parent_span_id
  end

  private

  def run_workflow(path)
    dir = File.dirname(path)
    params = ::Roast::WorkflowParams.new([], [], {})
    context = ::Roast::WorkflowContext.new(params: params, tmpdir: dir, workflow_dir: Pathname.new(dir))
    workflow = ::Roast::Workflow.new(path, context)
    workflow.prepare!
    workflow.start!
  end

  def with_workflow(source)
    Dir.mktmpdir("roast-test") do |dir|
      path = File.join(dir, "workflow.rb")
      File.write(path, source)
      yield path
    end
  end
end
