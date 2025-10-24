# frozen_string_literal: true

# Test with OpenAI gem 0.33.x (previous stable version)
appraise "openai-0.33" do
  gem "openai", "~> 0.33.0"
end

# Test with current stable OpenAI gem version
appraise "openai-0.34" do
  gem "openai", "~> 0.34.0"
end

# Test with latest OpenAI gem version (allows newer patch/minor versions)
appraise "openai-latest" do
  gem "openai", ">= 0.34"
end

# Test without OpenAI gem (verify SDK works without optional dependency)
appraise "openai-uninstalled" do
  remove_gem "openai"
end
