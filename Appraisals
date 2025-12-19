# frozen_string_literal: true

# Additional dependencies needed for specific gems.
# These work around upstream gems that haven't declared dependencies properly.
# See docs/appraisal-ruby-version-support.md for future Ruby version support.
GEM_DEPENDENCIES = {
  "openai" => ["base64"] # openai uses base64 but doesn't declare it (needed for Ruby 3.4+)
}

def gem_dependencies_for(gem_name)
  GEM_DEPENDENCIES.fetch(gem_name, [])
end

# Optional dependencies to test
OPTIONAL_GEMS = {
  "openai" => {
    "0.33" => "~> 0.33.0",
    "0.34" => "~> 0.34.0",
    "latest" => ">= 0.34"
  },
  "anthropic" => {
    "1.11" => "~> 1.11.0",
    "1.12" => "~> 1.12.0",
    "latest" => ">= 1.11"
  },
  "ruby-openai" => {
    "7.0" => "~> 7.0",
    "8.0" => "~> 8.0",
    "latest" => ">= 8.0"
  },
  "ruby_llm" => {
    "1.8" => "~> 1.8.0",
    "1.9" => "~> 1.9.0",
    "latest" => ">= 1.9"
  }
}

# Generate appraisals for each optional gem
OPTIONAL_GEMS.each do |gem_name, versions|
  extra_deps = gem_dependencies_for(gem_name)

  versions.each do |name, constraint|
    suffix = (name == "latest") ? "" : "-#{name.tr(".", "-")}"
    appraise "#{gem_name}#{suffix}" do
      gem gem_name, constraint
      extra_deps.each { |dep| gem dep }
    end
  end

  # Always test without gem installed
  appraise "#{gem_name}-uninstalled" do
    remove_gem gem_name
  end
end

# OpenTelemetry - test minimum and latest versions together
appraise "opentelemetry-min" do
  gem "opentelemetry-sdk", "~> 1.3.0"
  gem "opentelemetry-exporter-otlp", "~> 0.28.0"
end

appraise "opentelemetry-latest" do
  gem "opentelemetry-sdk", ">= 1.10"
  gem "opentelemetry-exporter-otlp", ">= 0.31"
end

# Both OpenAI gems installed - tests that loaded? correctly distinguishes them
appraise "openai-ruby-openai" do
  gem "openai", ">= 0.34"
  gem "ruby-openai", ">= 8.0"
end

# LLM libraries that can coexist - for demos that use multiple LLM SDKs
# Note: ruby-openai is excluded because it conflicts with the official openai gem
# (they share the same namespace). Use openai-ruby-openai appraisal to test both.
appraise "contrib" do
  gem "openai", ">= 0.34"
  gem "anthropic", ">= 1.11"
  gem "ruby_llm", ">= 1.9"
  gem "base64" # needed for openai gem on Ruby 3.4+
end
