# frozen_string_literal: true

module Braintrust
  module Trace
    # Middleware stack around an exporter's +export+, inspired by Sidekiq's
    # middleware chain.
    #
    # Prepend it once onto any exporter whose +export(span_data, timeout:)+ it
    # can +super+ into. Each middleware is an object that owns its own config
    # and responds to +call(spans) { |spans| ... }+: it yields (possibly
    # transformed) spans to continue down the stack, or returns an export
    # result without yielding to halt. The real export runs at the bottom.
    #
    #   class MyExporter < SomeOTelExporter
    #     prepend ExportMiddleware
    #
    #     middleware.add(SpanOrigin)      # class default, for every instance
    #   end
    #
    #   exporter = MyExporter.new
    #   exporter.middleware.add(SpanCustomizers.new(customizers))  # this instance only
    #
    # Instances start from a copy of their class's defaults, and subclasses from
    # a copy of their parent's. An instance's chain freezes on its first export,
    # so configure it before the exporter is handed to a span processor.
    #
    # @api private
    module ExportMiddleware
      # Ordered middleware entries. Entries are identified by class, or by the
      # module itself for stateless middleware such as SpanOrigin, and each
      # class appears at most once.
      class Chain
        def initialize(entries = [])
          @entries = entries
        end

        # Append middleware, replacing any existing entry of the same class.
        # @param middleware [#call] responds to call(spans) { |spans| ... }
        # @return [Chain] self
        def add(middleware)
          remove(key(middleware))
          @entries << middleware
          self
        end

        # @param klass [Module] class (or stateless module) of the entry to remove
        # @return [Chain] self
        def remove(klass)
          @entries.reject! { |entry| key(entry) == klass }
          self
        end

        # @param klass [Module]
        def exists?(klass)
          @entries.any? { |entry| key(entry) == klass }
        end

        # Insert middleware before the entry of class +anchor+, moving any
        # existing entry of the same class.
        # @raise [ArgumentError] if +anchor+ is not in the chain
        # @return [Chain] self
        def insert_before(anchor, middleware)
          insert(anchor, middleware, 0)
        end

        # Insert middleware after the entry of class +anchor+, moving any
        # existing entry of the same class.
        # @raise [ArgumentError] if +anchor+ is not in the chain
        # @return [Chain] self
        def insert_after(anchor, middleware)
          insert(anchor, middleware, 1)
        end

        # @return [Chain] self
        def clear
          @entries.clear
          self
        end

        # @return [Array<#call>] a copy of the entries, in order
        def entries
          @entries.dup
        end

        def freeze
          @entries.freeze
          super
        end

        # Run spans down the chain, ending in the given block.
        def invoke(spans, index = 0, &terminal)
          return terminal.call(spans) if index == @entries.size

          @entries[index].call(spans) { |downstream| invoke(downstream, index + 1, &terminal) }
        end

        def initialize_copy(source)
          super
          @entries = source.entries
        end

        private

        def insert(anchor, middleware, offset)
          raise ArgumentError, "#{anchor} is not in the middleware chain" unless exists?(anchor)

          remove(key(middleware))
          @entries.insert(@entries.index { |entry| key(entry) == anchor } + offset, middleware)
          self
        end

        def key(entry)
          entry.is_a?(Module) ? entry : entry.class
        end
      end

      def self.prepended(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Class-level defaults; a subclass starts from a copy of its parent's.
        def middleware
          @middleware ||= (superclass.is_a?(ClassMethods) ? superclass.middleware.dup : Chain.new)
        end
      end

      # This instance's chain, seeded from the class defaults.
      def middleware
        @middleware ||= self.class.middleware.dup
      end

      def export(span_data, timeout: nil)
        middleware.freeze.invoke(span_data) { |spans| super(spans, timeout: timeout) }
      end
    end
  end
end
