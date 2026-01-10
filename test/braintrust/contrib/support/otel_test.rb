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
end
