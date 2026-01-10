# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"
require_relative "../ruby_openai/integration_helper"

# This test verifies that the OpenAI integration correctly identifies when the
# official `openai` gem is loaded vs other OpenAI-like gems (e.g., ruby-openai).
#
# Tests are grouped by which gem scenario they verify:
#   OfficialOpenAIGemTest - runs with: appraisal openai
#   RubyOpenAIGemTest     - runs with: appraisal ruby-openai

# Tests that verify behavior when the official openai gem is available
class Braintrust::Contrib::OpenAI::OfficialOpenAIGemTest < Minitest::Test
  include Braintrust::Contrib::OpenAI::IntegrationHelper

  Integration = Braintrust::Contrib::OpenAI::Integration

  def setup
    skip_unless_openai!
  end

  def test_loaded_returns_true
    assert Integration.loaded?,
      "loaded? should return true when official openai gem is loaded"
  end

  def test_instrument_succeeds
    result = Braintrust.instrument!(:openai)

    # instrument! returns true if patching succeeded or was already done
    assert result, "instrument! should return truthy for official gem"

    # At least one patcher should be in patched state
    any_patched = Integration.patchers.any?(&:patched?)
    assert any_patched, "at least one patcher should be patched for official gem"
  end

  def test_openai_internal_is_defined
    # OpenAI::Internal should be defined for official gem
    assert defined?(::OpenAI::Internal),
      "OpenAI::Internal should be defined when official gem is loaded"
  end
end

# Tests that verify behavior when ruby-openai gem is loaded (not official openai)
class Braintrust::Contrib::OpenAI::RubyOpenAIGemTest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  Integration = Braintrust::Contrib::OpenAI::Integration

  def setup
    skip_unless_ruby_openai!
  end

  def test_loaded_returns_false
    # When ruby-openai is loaded, the OpenAI integration should NOT be loaded
    # because OpenAI::Internal is not defined
    refute Integration.loaded?,
      "loaded? should return false when ruby-openai gem is loaded"
  end

  def test_not_available
    # The OpenAI integration should NOT be available when only ruby-openai is loaded
    refute Integration.available?,
      "Should NOT be available when only ruby-openai gem is loaded"
  end
end
