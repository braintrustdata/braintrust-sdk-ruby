# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/support/otel"

class Braintrust::Contrib::Support::OTelTest < Minitest::Test
  # --- .set_json_attr ---

  def test_set_json_attr_sets_attribute_with_json
    span = Minitest::Mock.new
    span.expect(:set_attribute, nil, ["braintrust.output", '{"foo":"bar"}'])

    Braintrust::Contrib::Support::OTel.set_json_attr(span, "braintrust.output", {foo: "bar"})

    span.verify
  end

  def test_set_json_attr_skips_nil_object
    span = Minitest::Mock.new
    # No expectations - set_attribute should not be called

    Braintrust::Contrib::Support::OTel.set_json_attr(span, "braintrust.output", nil)

    span.verify
  end

  def test_set_json_attr_handles_array
    span = Minitest::Mock.new
    span.expect(:set_attribute, nil, ["braintrust.input", "[1,2,3]"])

    Braintrust::Contrib::Support::OTel.set_json_attr(span, "braintrust.input", [1, 2, 3])

    span.verify
  end

  def test_set_json_attr_inherits_context_metadata_for_metadata_attr
    parent_metadata = {"prompt_id" => "abc", "shared" => "parent"}
    child_metadata = {"provider" => "openai", "shared" => "child"}

    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", parent_metadata)
    OpenTelemetry::Context.with_current(context) do
      span = Minitest::Mock.new
      expected = JSON.generate({"prompt_id" => "abc", "shared" => "child", "provider" => "openai"})
      span.expect(:set_attribute, nil, ["braintrust.metadata", expected])

      Braintrust::Contrib::Support::OTel.set_json_attr(span, "braintrust.metadata", child_metadata)

      span.verify
    end
  end

  def test_set_json_attr_does_not_inherit_for_non_metadata_attrs
    parent_metadata = {"prompt_id" => "abc"}
    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", parent_metadata)
    OpenTelemetry::Context.with_current(context) do
      span = Minitest::Mock.new
      span.expect(:set_attribute, nil, ["braintrust.output", '{"foo":"bar"}'])

      Braintrust::Contrib::Support::OTel.set_json_attr(span, "braintrust.output", {"foo" => "bar"})

      span.verify
    end
  end

  # --- .inherit_context_metadata! ---

  def test_inherit_context_metadata_merges_parent_with_child_winning
    parent_metadata = {"prompt_id" => "abc", "shared" => "parent"}
    child_metadata = {"provider" => "openai", "shared" => "child"}

    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", parent_metadata)
    OpenTelemetry::Context.with_current(context) do
      Braintrust::Contrib::Support::OTel.inherit_context_metadata!(child_metadata)
    end

    assert_equal({"prompt_id" => "abc", "provider" => "openai", "shared" => "child"}, child_metadata)
  end

  def test_inherit_context_metadata_deep_merges_nested_hashes
    parent_metadata = {"origin" => {"type" => "prompt", "id" => "abc", "version" => "1"}}
    child_metadata = {"origin" => {"type" => "override"}}

    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", parent_metadata)
    OpenTelemetry::Context.with_current(context) do
      Braintrust::Contrib::Support::OTel.inherit_context_metadata!(child_metadata)
    end

    assert_equal({"origin" => {"type" => "override", "id" => "abc", "version" => "1"}}, child_metadata)
  end

  def test_inherit_context_metadata_noop_without_parent
    child_metadata = {"provider" => "openai"}

    Braintrust::Contrib::Support::OTel.inherit_context_metadata!(child_metadata)

    assert_equal({"provider" => "openai"}, child_metadata)
  end

  def test_inherit_context_metadata_noop_for_non_hash_parent
    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", "not a hash")
    OpenTelemetry::Context.with_current(context) do
      child_metadata = {"provider" => "openai"}

      Braintrust::Contrib::Support::OTel.inherit_context_metadata!(child_metadata)

      assert_equal({"provider" => "openai"}, child_metadata)
    end
  end

  def test_inherit_context_metadata_noop_for_non_hash_metadata
    parent_metadata = {"prompt_id" => "abc"}
    context = OpenTelemetry::Context.current.set_value("braintrust.metadata", parent_metadata)
    OpenTelemetry::Context.with_current(context) do
      # Should not raise
      Braintrust::Contrib::Support::OTel.inherit_context_metadata!(nil)
      Braintrust::Contrib::Support::OTel.inherit_context_metadata!("string")
    end
  end
end
