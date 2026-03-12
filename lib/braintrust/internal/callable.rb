# frozen_string_literal: true

module Braintrust
  module Internal
    module Callable
      # Filters keyword arguments so callers can pass a superset of kwargs
      # and the receiver only gets the ones it declared. This avoids Ruby 3.2+
      # ArgumentError for unknown keywords without requiring ** on every definition.
      #
      # When prepended on a class, intercepts #call and slices kwargs to match
      # the declared parameters before forwarding. Methods with **keyrest
      # receive all kwargs unfiltered.
      #
      # @example
      #   class Greeter
      #     prepend Internal::Callable::KeywordFilter
      #     def call(name:)
      #       "hello #{name}"
      #     end
      #   end
      #   Greeter.new.call(name: "world", extra: "ignored")  # => "hello world"
      module KeywordFilter
        # Filter kwargs to only the keyword params declared by the given parameters list.
        # Returns kwargs unchanged if parameters include **keyrest.
        #
        # @param params [Array<Array>] parameter list from Proc#parameters or Method#parameters
        # @param kwargs [Hash] keyword arguments to filter
        # @return [Hash] filtered keyword arguments
        def self.filter(params, kwargs)
          return kwargs if has_keyword_splat?(params)

          declared_keys = params
            .select { |type, _| type == :keyreq || type == :key }
            .map(&:last)
          kwargs.slice(*declared_keys)
        end

        # Wrap a Proc to filter kwargs to only its declared keyword params.
        # Returns the block unchanged if it accepts **keyrest.
        #
        # @param block [Proc] the block to wrap
        # @return [Proc] a wrapper that filters kwargs, or the original block
        def self.wrap_block(block)
          return block if has_keyword_splat?(block.parameters)
          ->(**kw) { block.call(**filter(block.parameters, kw)) }
        end

        # Whether params include ** (keyword splat / keyrest).
        #
        # @param params [Array<Array>] parameter list
        # @return [Boolean]
        def self.has_keyword_splat?(params)
          params.any? { |type, _| type == :keyrest }
        end

        # Whether params include any keyword parameters (key, keyreq, or keyrest).
        #
        # @param params [Array<Array>] parameter list
        # @return [Boolean]
        def self.has_any_keywords?(params)
          params.any? { |type, _| type == :keyreq || type == :key || type == :keyrest }
        end

        # When prepended, filters kwargs before the next #call in the ancestor chain.
        # If the instance defines #call_parameters, uses those.
        # Otherwise introspects super_method.
        #
        # @param kwargs [Hash] keyword arguments
        # @return [Object] result of the filtered #call
        def call(**kwargs)
          params = if respond_to?(:call_parameters)
            call_parameters
          else
            impl = method(:call).super_method
            return super unless impl
            impl.parameters
          end
          super(**KeywordFilter.filter(params, kwargs))
        end
      end
    end
  end
end
