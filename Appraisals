# frozen_string_literal: true

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
  versions.each do |name, constraint|
    suffix = (name == "latest") ? "" : "-#{name.tr(".", "-")}"
    appraise "#{gem_name}#{suffix}" do
      gem gem_name, constraint
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
