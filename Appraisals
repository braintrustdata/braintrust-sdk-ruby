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
appraise "openai" do
  gem "openai", ">= 0.34"
end

# Test without OpenAI gem (verify SDK works without optional dependency)
appraise "openai-uninstalled" do
  remove_gem "openai"
end

# Test with Anthropic gem 1.11.x (recent stable version)
appraise "anthropic-1.11" do
  gem "anthropic", "~> 1.11.0"
end

# Test with Anthropic gem 1.12.x (latest stable version)
appraise "anthropic-1.12" do
  gem "anthropic", "~> 1.12.0"
end

# Test with latest Anthropic gem version (allows newer versions)
appraise "anthropic" do
  gem "anthropic", ">= 1.11"
end

# Test without Anthropic gem (verify SDK works without optional dependency)
appraise "anthropic-uninstalled" do
  remove_gem "anthropic"
end

# Test with latest RubyLLM gem version
appraise "ruby_llm" do
  gem "ruby_llm", ">= 1.0"
end

# Test without RubyLLM gem (verify SDK works without optional dependency)
appraise "ruby_llm-uninstalled" do
  remove_gem "ruby_llm"
end
