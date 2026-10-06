# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::ExportMiddlewareTest < Minitest::Test
  Chain = Braintrust::Trace::ExportMiddleware::Chain

  # Records what reaches the real export, standing in for an OTel exporter.
  class BaseExporter
    attr_reader :exported

    def export(span_data, timeout: nil)
      (@exported ||= []) << {spans: span_data, timeout: timeout}
      0
    end
  end

  class Exporter < BaseExporter
    prepend Braintrust::Trace::ExportMiddleware
  end

  # Appends a marker to each span, then passes on.
  class Tag
    attr_reader :tag

    def initialize(tag) = @tag = tag

    def call(spans) = yield(spans.map { |span| "#{span}+#{@tag}" })
  end

  class OtherTag < Tag; end

  # Stateless middleware, registered as the module itself (like SpanOrigin).
  module Upcase
    def self.call(spans) = yield(spans.map(&:upcase))
  end

  class Halt
    def call(_spans) = 1
  end

  # Exporter behavior

  def test_runs_middleware_in_order_then_exports_with_timeout
    exporter = Exporter.new
    exporter.middleware.add(Tag.new("a")).add(Upcase)

    assert_equal 0, exporter.export(%w[span], timeout: 5)
    assert_equal [{spans: ["SPAN+A"], timeout: 5}], exporter.exported
  end

  def test_middleware_can_halt_without_exporting
    exporter = Exporter.new
    exporter.middleware.add(Halt.new)

    assert_equal 1, exporter.export(%w[span])
    assert_nil exporter.exported
  end

  def test_middleware_can_wrap_the_export_result
    seen = nil
    around = Object.new
    around.define_singleton_method(:call) { |spans, &downstream| seen = downstream.call(spans) }
    exporter = Exporter.new
    exporter.middleware.add(around)

    exporter.export(%w[span])
    assert_equal 0, seen
  end

  def test_instances_start_from_class_defaults_without_sharing_additions
    klass = Class.new(BaseExporter) { prepend Braintrust::Trace::ExportMiddleware }
    klass.middleware.add(Tag.new("default"))
    first = klass.new
    first.middleware.add(OtherTag.new("instance"))
    second = klass.new

    first.export(%w[x])
    second.export(%w[x])
    assert_equal ["x+default+instance"], first.exported.fetch(0)[:spans]
    assert_equal ["x+default"], second.exported.fetch(0)[:spans]
  end

  def test_subclasses_inherit_class_defaults
    parent = Class.new(BaseExporter) { prepend Braintrust::Trace::ExportMiddleware }
    parent.middleware.add(Tag.new("parent"))

    exporter = Class.new(parent).new
    exporter.export(%w[x])
    assert_equal ["x+parent"], exporter.exported.fetch(0)[:spans]
  end

  def test_instance_chain_is_frozen_after_first_export
    exporter = Exporter.new
    exporter.export(%w[x])

    assert_raises(FrozenError) { exporter.middleware.add(Tag.new("late")) }
    assert_raises(FrozenError) { exporter.middleware.remove(Tag) }
  end

  # Chain API

  def test_add_replaces_an_entry_of_the_same_class
    chain = Chain.new.add(Tag.new("old")).add(Upcase).add(Tag.new("new"))

    assert_equal [Upcase, Tag], chain.entries.map { |entry| entry.is_a?(Module) ? entry : entry.class }
    assert_equal "new", chain.entries.last.tag
  end

  def test_remove_and_exists_match_by_class_or_module
    chain = Chain.new.add(Tag.new("a")).add(Upcase)

    assert chain.exists?(Tag)
    assert chain.exists?(Upcase)
    refute chain.exists?(Halt)
    chain.remove(Tag).remove(Upcase)
    assert_empty chain.entries
  end

  def test_insert_before_and_after
    chain = Chain.new.add(Upcase)
    chain.insert_before(Upcase, Tag.new("before"))
    chain.insert_after(Upcase, Halt.new)

    assert_equal [Tag, Upcase, Halt], chain.entries.map { |entry| entry.is_a?(Module) ? entry : entry.class }
  end

  def test_insert_moves_an_existing_entry_of_the_same_class
    chain = Chain.new.add(Upcase).add(Tag.new("old"))
    chain.insert_before(Upcase, Tag.new("new"))

    assert_equal %w[new], chain.entries.grep(Tag).map(&:tag)
    assert_equal Upcase, chain.entries.last
  end

  def test_insert_relative_to_a_missing_entry_raises
    error = assert_raises(ArgumentError) { Chain.new.insert_before(Upcase, Tag.new("x")) }
    assert_match(/Upcase/, error.message)
  end

  def test_clear
    assert_empty Chain.new.add(Upcase).clear.entries
  end

  def test_entries_is_a_copy
    chain = Chain.new.add(Upcase)
    chain.entries.clear

    assert chain.exists?(Upcase)
  end
end
