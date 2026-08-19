# frozen_string_literal: true

# Optional dependencies to test.
# Each version entry is a hash with:
#   constraint: version constraint for the gem
#   deps: hash of additional gem dependencies to install, mapping gem name to
#         constraint (or nil for no constraint). Works around upstream gems that
#         haven't declared dependencies properly (e.g. base64/cgi removed from stdlib).
OPTIONAL_GEMS = {
  "openai" => {
    "0.33" => {constraint: "~> 0.33.0", deps: {"base64" => nil, "cgi" => nil}},
    "0.34" => {constraint: "~> 0.34.0", deps: {"base64" => nil, "cgi" => nil}},
    "latest" => {constraint: ">= 0.34", deps: {"base64" => nil, "cgi" => nil}}
  },
  "anthropic" => {
    "1.11" => {constraint: "~> 1.11.0", deps: {"base64" => nil, "cgi" => nil}},
    "1.12" => {constraint: "~> 1.12.0", deps: {"base64" => nil, "cgi" => nil}},
    "latest" => {constraint: ">= 1.11", deps: {"base64" => nil, "cgi" => nil}}
  },
  "ruby-openai" => {
    "7.0" => {constraint: "~> 7.0", deps: {}},
    "8.0" => {constraint: "~> 8.0", deps: {}},
    "latest" => {constraint: ">= 8.0", deps: {}}
  },
  "ruby_llm" => {
    "1.8" => {constraint: "~> 1.8.0", deps: {}},
    "1.9" => {constraint: "~> 1.9.0", deps: {}},
    "latest" => {constraint: ">= 1.9", deps: {}}
  },
  "llm.rb" => {
    "4.11" => {constraint: "~> 4.11.0", deps: {}},
    "latest" => {constraint: ">= 4.11", deps: {}}
  }
}

# Generate appraisals for each optional gem
OPTIONAL_GEMS.each do |gem_name, versions|
  versions.each do |name, config|
    suffix = (name == "latest") ? "" : "-#{name.tr(".", "-")}"
    appraise "#{gem_name}#{suffix}" do
      gem gem_name, config[:constraint]
      config[:deps].each { |dep, version| gem dep, *[version].compact }
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
  gem "cgi" # needed for openai/anthropic gems on Ruby 4.0+
end

# Server testing - all latest LLM SDKs + server deps for eval dev server
appraise "server" do
  gem "openai", ">= 0.34"
  gem "anthropic", ">= 1.11"
  gem "ruby_llm", ">= 1.9"
  gem "base64" # needed for openai gem on Ruby 3.4+
  gem "cgi" # needed for openai/anthropic gems on Ruby 4.0+
  gem "rack", "~> 3.0"
  gem "rack-test", "~> 2.1"
  gem "rackup", "~> 2.3"
  gem "puma", "~> 6.0"
  gem "falcon", "~> 0.48"
  gem "passenger", "~> 6.0"
end

# Rails integration testing (minimal dependencies)
appraise "rails" do
  gem "activesupport", "~> 8.0"
  gem "railties", "~> 8.0"
end

# Rails engine testing for the eval server engine
appraise "rails-server" do
  gem "actionpack", "~> 8.0"
  gem "railties", "~> 8.0"
  gem "activesupport", "~> 8.0"
  gem "rack", "~> 3.0"
  gem "rack-test", "~> 2.1"
end
