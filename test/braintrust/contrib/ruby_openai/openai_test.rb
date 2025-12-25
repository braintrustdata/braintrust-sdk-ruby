# frozen_string_literal: true

# require "test_helper"

# # Load the openai gem to define OpenAI::Client (and OpenAI::Internal if official gem)
# # This must happen before tests run so the gem detection logic works
# begin
#   require "openai"
# rescue LoadError
#   # Gem not available in this appraisal
# end

# This test verifies that the RubyOpenAI integration correctly identifies when the
# `ruby-openai` gem is loaded vs the official `openai` gem.
#
# The test is designed to work with different appraisals:
#   bundle exec appraisal ruby-openai rake test:contrib  # ruby-openai only - tests run
#   bundle exec appraisal openai-ruby-openai rake test:contrib  # Both gems - tests skipped (ruby-openai loads)
#   bundle exec appraisal openai rake test:contrib       # Official gem only - tests skipped
#
# The test verifies:
# 1. When `ruby-openai` gem is loaded, loaded? returns true
# 2. When `ruby-openai` gem is loaded, instrument! succeeds and patchers are applied

class Braintrust::Contrib::RubyOpenAI::OpenAITest < Minitest::Test
  Integration = Braintrust::Contrib::RubyOpenAI::Integration

  # def ruby_openai_available?
  #   # OpenAI::Internal is only defined in the official openai gem
  #   !Gem.loaded_specs["ruby-openai"].nil?
  # end

  # def official_openai_available?
  #   # OpenAI::Internal is only defined in the official openai gem
  #   !Gem.loaded_specs["openai"].nil?
  # end

  def ruby_openai_loaded?
    # Check if ruby-openai gem is loaded (not the official openai gem).
    # Both gems use "require 'openai'", so we need to distinguish them.
    #
    # OpenAI::Internal is defined ONLY in the official OpenAI gem
    (defined?(::OpenAI::Client) && !defined?(::OpenAI::Internal)) ? true : false
  end

  # --- .loaded? ---

  def test_loaded_returns_true_for_ruby_openai_gem
    skip "ruby-openai gem not loaded" unless ruby_openai_loaded?

    assert Integration.loaded?,
      "loaded? should return true when ruby-openai gem is loaded"
  end

  def test_loaded_returns_false_when_ruby_openai_gem_not_loaded
    skip "ruby-openai gem is loaded" if ruby_openai_loaded?

    refute Integration.loaded?,
      "loaded? should return false when ruby-openai gem is not loaded"
  end

  # --- Braintrust.instrument! ---

  def test_instrument_succeeds_for_ruby_openai_gem
    skip "ruby-openai gem not loaded" unless ruby_openai_loaded?

    result = Braintrust.instrument!(:ruby_openai)

    assert result, "instrument! should return truthy for ruby-openai gem"

    any_patched = Integration.patchers.any?(&:patched?)
    assert any_patched, "at least one patcher should be patched for ruby-openai gem"
  end

  # --- OpenAI::Internal ---

  def test_openai_internal_not_defined_for_ruby_openai_gem
    skip "ruby-openai gem not loaded" unless ruby_openai_loaded?

    refute defined?(::OpenAI::Internal),
      "OpenAI::Internal should not be defined when ruby-openai gem is loaded"
  end

  # --- .available? ---

  def test_not_available_when_official_openai_gem_loaded
    skip "ruby-openai gem is available" if Gem.loaded_specs["ruby-openai"]
    skip "Official openai gem not loaded" unless Gem.loaded_specs["openai"]

    refute Integration.available?, "Should NOT be available when only official openai gem is loaded"
  end
end
