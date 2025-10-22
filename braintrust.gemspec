# frozen_string_literal: true

require_relative "lib/braintrust/version"

Gem::Specification.new do |spec|
  spec.name = "braintrust"
  spec.version = Braintrust::VERSION
  spec.authors = ["Braintrust"]
  spec.email = ["info@braintrust.dev"]

  spec.summary = "Ruby SDK for Braintrust"
  spec.description = "OpenTelemetry-based SDK for Braintrust with tracing, OpenAI integration, and evals"
  spec.homepage = "https://github.com/braintrustdata/braintrust-sdk-ruby"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[
    lib/**/*.rb
    README.md
    LICENSE
    CHANGELOG.md
  ])
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "opentelemetry-sdk", "~> 1.0"
  spec.add_runtime_dependency "opentelemetry-exporter-otlp", "~> 0.28"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "openai", "~> 0.34"
end
