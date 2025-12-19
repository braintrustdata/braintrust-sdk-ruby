# frozen_string_literal: true

require "test_helper"

# This test verifies that the OpenAI integration correctly identifies when the
# official `openai` gem is loaded vs other OpenAI-like gems (e.g., ruby-openai).
#
# The test is designed to work with different appraisals:
#   bundle exec appraisal openai rake test:contrib       # Official gem only - tests run
#   bundle exec appraisal openai-ruby-openai rake test:contrib  # Both gems - tests skipped (ruby-openai loads)
#   bundle exec appraisal ruby-openai rake test:contrib  # ruby-openai only - tests skipped
#
# The test verifies:
# 1. When official `openai` gem is loaded, loaded? returns true
# 2. When official `openai` gem is loaded, instrument! succeeds and patchers are applied

class Braintrust::Contrib::OpenAI::RubyOpenAITest < Minitest::Test
  Integration = Braintrust::Contrib::OpenAI::Integration

  def official_openai_loaded?
    # OpenAI::Internal is only defined in the official openai gem
    defined?(::OpenAI::Internal) ? true : false
  end

  def test_loaded_returns_true_for_official_gem
    skip "Official openai gem not loaded" unless official_openai_loaded?

    require "openai"

    assert Integration.loaded?,
      "loaded? should return true when official openai gem is loaded"
  end

  def test_loaded_returns_false_when_official_gem_not_loaded
    skip "Official openai gem is loaded" if official_openai_loaded?

    # When official gem is not loaded, loaded? should be false
    # This covers both "no gem at all" and "ruby-openai loaded instead"
    refute Integration.loaded?,
      "loaded? should return false when official openai gem is not loaded"
  end

  def test_instrument_succeeds_for_official_gem
    skip "Official openai gem not loaded" unless official_openai_loaded?

    require "openai"

    result = Braintrust.instrument!(:openai)

    # instrument! returns true if patching succeeded or was already done
    assert result, "instrument! should return truthy for official gem"

    # At least one patcher should be in patched state
    any_patched = Integration.patchers.any?(&:patched?)
    assert any_patched, "at least one patcher should be patched for official gem"
  end

  def test_openai_internal_identifies_official_gem
    skip "Official openai gem not loaded" unless official_openai_loaded?

    require "openai"

    # OpenAI::Internal should be defined for official gem
    assert defined?(::OpenAI::Internal),
      "OpenAI::Internal should be defined when official gem is loaded"
  end

  def test_not_available_when_ruby_openai_gem_loaded
    # The ruby-openai gem also uses 'openai' in require path but has different gem name
    # It should NOT match because Gem.loaded_specs won't have "openai" key (it has "ruby-openai")
    # Check Gem.loaded_specs (not official_openai_loaded?) because the gem may not be required yet
    skip "Official openai gem is available" if Gem.loaded_specs["openai"]
    skip "ruby-openai gem not loaded" unless Gem.loaded_specs["ruby-openai"]

    refute Integration.available?, "Should NOT be available when only ruby-openai gem is loaded"
  end
end
