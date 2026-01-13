# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::ContextTest < Minitest::Test
  def setup
    @target = Object.new
  end

  def test_from_returns_nil_for_nil_target
    assert_nil Braintrust::Contrib::Context.from(nil)
  end

  def test_from_returns_nil_when_no_context_set
    assert_nil Braintrust::Contrib::Context.from(@target)
  end

  def test_from_returns_context_when_set
    Braintrust::Contrib::Context.set!(@target, foo: "bar")

    ctx = Braintrust::Contrib::Context.from(@target)

    assert_instance_of Braintrust::Contrib::Context, ctx
  end

  def test_set_creates_context_with_options
    Braintrust::Contrib::Context.set!(@target, foo: "bar", baz: 123)

    ctx = Braintrust::Contrib::Context.from(@target)

    assert_equal "bar", ctx[:foo]
    assert_equal 123, ctx[:baz]
  end

  def test_set_returns_nil_when_creating_new_context
    result = Braintrust::Contrib::Context.set!(@target, foo: "bar")

    assert_nil result
  end

  def test_set_returns_nil_with_empty_options
    result = Braintrust::Contrib::Context.set!(@target)

    assert_nil result
    assert_nil Braintrust::Contrib::Context.from(@target)
  end

  def test_set_updates_existing_context
    Braintrust::Contrib::Context.set!(@target, foo: "bar")
    Braintrust::Contrib::Context.set!(@target, baz: 123)

    ctx = Braintrust::Contrib::Context.from(@target)

    assert_equal "bar", ctx[:foo]
    assert_equal 123, ctx[:baz]
  end

  def test_set_overwrites_existing_keys
    Braintrust::Contrib::Context.set!(@target, foo: "bar")
    Braintrust::Contrib::Context.set!(@target, foo: "updated")

    ctx = Braintrust::Contrib::Context.from(@target)

    assert_equal "updated", ctx[:foo]
  end

  def test_context_bracket_access
    ctx = Braintrust::Contrib::Context.new(foo: "bar")

    assert_equal "bar", ctx[:foo]
    assert_nil ctx[:missing]
  end

  def test_context_bracket_assignment
    ctx = Braintrust::Contrib::Context.new

    ctx[:foo] = "bar"

    assert_equal "bar", ctx[:foo]
  end

  def test_context_fetch_returns_value
    ctx = Braintrust::Contrib::Context.new(foo: "bar")

    assert_equal "bar", ctx.fetch(:foo, "default")
  end

  def test_context_fetch_returns_default_when_missing
    ctx = Braintrust::Contrib::Context.new

    assert_equal "default", ctx.fetch(:missing, "default")
  end
end
