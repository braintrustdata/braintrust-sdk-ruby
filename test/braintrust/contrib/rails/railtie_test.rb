# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

module Braintrust
  module Contrib
    module Rails
      class RailtieTest < Minitest::Test
        include IntegrationHelper

        def test_railtie_callback_calls_auto_instrument
          skip_unless_rails!

          assert_in_fork do
            require "active_support"
            require "rails/railtie"

            # Capture the after_initialize block when the railtie is loaded
            captured_block = nil
            original_after_init = ::Rails::Railtie::Configuration.instance_method(:after_initialize)
            ::Rails::Railtie::Configuration.define_method(:after_initialize) do |&block|
              captured_block = block
            end

            require "braintrust/contrib/rails/railtie"

            # Restore original method
            ::Rails::Railtie::Configuration.define_method(:after_initialize, original_after_init)

            auto_instrument_called_with = nil
            Braintrust.stub(:auto_instrument!, ->(**kwargs) { auto_instrument_called_with = kwargs }) do
              captured_block.call
            end

            if auto_instrument_called_with == {only: nil, except: nil}
              puts "callback_test:passed"
            else
              puts "callback_test:failed - got #{auto_instrument_called_with.inspect}"
              exit 1
            end
          end
        end

        def test_railtie_passes_only_from_env
          skip_unless_rails!

          assert_in_fork do
            ENV["BRAINTRUST_INSTRUMENT_ONLY"] = "openai,anthropic"

            require "active_support"
            require "rails/railtie"

            captured_block = nil
            original_after_init = ::Rails::Railtie::Configuration.instance_method(:after_initialize)
            ::Rails::Railtie::Configuration.define_method(:after_initialize) do |&block|
              captured_block = block
            end

            require "braintrust/contrib/rails/railtie"

            ::Rails::Railtie::Configuration.define_method(:after_initialize, original_after_init)

            auto_instrument_called_with = nil
            Braintrust.stub(:auto_instrument!, ->(**kwargs) { auto_instrument_called_with = kwargs }) do
              captured_block.call
            end

            expected = {only: [:openai, :anthropic], except: nil}
            if auto_instrument_called_with == expected
              puts "only_env_test:passed"
            else
              puts "only_env_test:failed - expected #{expected.inspect}, got #{auto_instrument_called_with.inspect}"
              exit 1
            end
          end
        end

        def test_railtie_passes_except_from_env
          skip_unless_rails!

          assert_in_fork do
            ENV["BRAINTRUST_INSTRUMENT_EXCEPT"] = "ruby_llm"

            require "active_support"
            require "rails/railtie"

            captured_block = nil
            original_after_init = ::Rails::Railtie::Configuration.instance_method(:after_initialize)
            ::Rails::Railtie::Configuration.define_method(:after_initialize) do |&block|
              captured_block = block
            end

            require "braintrust/contrib/rails/railtie"

            ::Rails::Railtie::Configuration.define_method(:after_initialize, original_after_init)

            auto_instrument_called_with = nil
            Braintrust.stub(:auto_instrument!, ->(**kwargs) { auto_instrument_called_with = kwargs }) do
              captured_block.call
            end

            expected = {only: nil, except: [:ruby_llm]}
            if auto_instrument_called_with == expected
              puts "except_env_test:passed"
            else
              puts "except_env_test:failed - expected #{expected.inspect}, got #{auto_instrument_called_with.inspect}"
              exit 1
            end
          end
        end
      end
    end
  end
end
