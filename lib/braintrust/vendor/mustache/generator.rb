# frozen_string_literal: true

# Vendored from mustache gem v1.1.1
# https://github.com/mustache/mustache
# License: MIT
# Modifications: Namespaced under Braintrust::Vendor

module Braintrust
  module Vendor
    class Mustache
      # The Generator is in charge of taking an array of Mustache tokens,
      # usually assembled by the Parser, and generating an interpolatable
      # Ruby string. This string is considered the "compiled" template
      # because at that point we're relying on Ruby to do the parsing and
      # run our code.
      #
      # For example, let's take this template:
      #
      #   Hi {{thing}}!
      #
      # If we run this through the Parser we'll get these tokens:
      #
      #   [:multi,
      #     [:static, "Hi "],
      #     [:mustache, :etag, "thing"],
      #     [:static, "!\n"]]
      #
      # Now let's hand that to the Generator:
      #
      # >> puts Braintrust::Vendor::Mustache::Generator.new.compile(tokens)
      # "Hi #{ctx.escape(ctx[:thing])}!\n"
      class Generator
        # Options can be used to manipulate the resulting ruby code string behavior.
        def initialize(options = {})
          @options = options
          @option_static_lambdas = options[:static_lambdas] == true
        end

        # Given an array of tokens, returns an interpolatable Ruby string.
        def compile(exp)
          "\"#{compile!(exp)}\""
        end

        private

        # Given an array of tokens, converts them into Ruby code. In
        # particular there are three types of expressions we are concerned
        # with:
        #
        #   :multi
        #     Mixed bag of :static, :mustache, and whatever.
        #
        #   :static
        #     Normal HTML, the stuff outside of {{mustaches}}.
        #
        #   :mustache
        #     Any Mustache tag, from sections to partials.
        def compile!(exp)
          case exp.first
          when :multi
            exp[1..-1].reduce(+"") { |sum, e| sum << compile!(e) }
          when :static
            str(exp[1])
          when :mustache
            send(:"on_#{exp[1]}", *exp[2..-1])
          else
            raise "Unhandled exp: #{exp.first}"
          end
        end

        # Callback fired when the compiler finds a section token. We're
        # passed the section name and the array of tokens.
        def on_section(name, offset, content, raw, delims)
          # Convert the tokenized content of this section into a Ruby
          # string we can use.
          code = compile(content)

          # Lambda handling - default handling is to dynamically interpret
          # the returned lambda result as mustache source
          proc_handling = if @option_static_lambdas
            <<-compiled
              v.call(lambda {|v| #{code}}.call(v)).to_s
            compiled
          else
            <<-compiled
              t = Braintrust::Vendor::Mustache::Template.new(v.call(#{raw.inspect}).to_s)
              def t.tokens(src=@source)
                p = Braintrust::Vendor::Mustache::Parser.new
                p.otag, p.ctag = #{delims.inspect}
                p.compile(src)
              end
              t.render(ctx.dup)
            compiled
          end

          # Compile the Ruby for this section now that we know what's
          # inside the section.
          ev(<<-compiled)
          case v = #{compile!(name)}
          when NilClass, FalseClass
          when TrueClass
            #{code}
          when Proc
            #{proc_handling}
          when Array, Enumerator, Braintrust::Vendor::Mustache::Enumerable
            v.map { |_| ctx.push(_); r = #{code}; ctx.pop; r }.join
          else
            ctx.push(v); r = #{code}; ctx.pop; r
          end
          compiled
        end

        # Fired when we find an inverted section. Just like `on_section`,
        # we're passed the inverted section name and the array of tokens.
        def on_inverted_section(name, offset, content, raw, delims)
          # Convert the tokenized content of this section into a Ruby
          # string we can use.
          code = compile(content)

          # Compile the Ruby for this inverted section now that we know
          # what's inside.
          ev(<<-compiled)
          v = #{compile!(name)}
          if v.nil? || v == false || v.respond_to?(:empty?) && v.empty?
            #{code}
          end
          compiled
        end

        # Fired when the compiler finds a partial. We want to return code
        # which calls a partial at runtime instead of expanding and
        # including the partial's body to allow for recursive partials.
        def on_partial(name, offset, indentation)
          ev("ctx.partial(#{name.to_sym.inspect}, #{indentation.inspect})")
        end

        # An unescaped tag.
        def on_utag(name, offset)
          ev(<<-compiled)
            v = #{compile!(name)}
            if v.is_a?(Proc)
              v = #{@option_static_lambdas ? "v.call" : "Braintrust::Vendor::Mustache::Template.new(v.call.to_s).render(ctx.dup)"}
            end
            v.to_s
          compiled
        end

        # An escaped tag.
        def on_etag(name, offset)
          ev(<<-compiled)
            v = #{compile!(name)}
            if v.is_a?(Proc)
              v = #{@option_static_lambdas ? "v.call" : "Braintrust::Vendor::Mustache::Template.new(v.call.to_s).render(ctx.dup)"}
            end
            ctx.escape(v)
          compiled
        end

        def on_fetch(names)
          return "ctx.current" if names.empty?

          names = names.map { |n| n.to_sym }

          initial, *rest = names
          if rest.any?
            <<-compiled
              #{rest.inspect}.reduce(ctx[#{initial.inspect}]) { |value, key| value && ctx.find(value, key) }
            compiled
          else
            <<-compiled
              ctx[#{initial.inspect}]
            compiled
          end
        end

        # An interpolation-friendly version of a string, for use within a
        # Ruby string.
        def ev(s)
          "#\{#{s}}"
        end

        def str(s)
          s.inspect[1..-2]
        end
      end
    end
  end
end
