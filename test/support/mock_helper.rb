module Test
  module Support
    module MockHelper
      # Build a chain of mocks for nested method calls.
      # Useful for testing code that traverses object hierarchies like `obj.foo.bar.baz`.
      #
      # Creates intermediate mocks that return each other in sequence, with the final
      # mock returning the specified terminal value. All intermediate mocks are verified
      # after the block. The caller is responsible for verifying the terminal value if needed.
      #
      # @param methods [Array<Symbol>] chain of method names to mock
      # @param returns [Object] the value returned by the final method (can be a Class, Mock, or any object)
      # @yield [root] the root mock (entry point to the chain)
      #
      # @example Testing a method chain with a Class as terminal
      #   fake_singleton = Class.new { include SomeModule }
      #   mock_chain(:chat, :completions, :singleton_class, returns: fake_singleton) do |client|
      #     assert SomePatcher.patched?(target: client)
      #   end
      #
      # @example Testing a method chain with a Mock as terminal
      #   terminal = Minitest::Mock.new
      #   terminal.expect(:include, true, [SomeModule])
      #   mock_chain(:foo, :bar, returns: terminal) do |root|
      #     SomeCode.do_something(root)
      #   end
      #   terminal.verify
      #
      def mock_chain(*methods, returns:)
        current = returns
        mocks = []

        methods.reverse_each do |method|
          mock = Minitest::Mock.new
          mock.expect(method, current)
          mocks.unshift(mock)
          current = mock
        end

        yield(mocks.first)

        mocks.each(&:verify)
      end
    end
  end
end
