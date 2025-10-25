# frozen_string_literal: true

require_relative "lib/braintrust/version"

Gem::Specification.new do |spec|
  spec.name = "braintrust"
  spec.version = Braintrust::VERSION
  spec.authors = ["Braintrust"]
  spec.email = ["info@braintrust.dev"]

  spec.summary = "Ruby SDK for Braintrust"
  spec.description = "Braintrust Ruby SDK for evals, tracing and more. "
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
  ])
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "opentelemetry-sdk", "~> 1.0"
  spec.add_runtime_dependency "opentelemetry-exporter-otlp", "~> 0.28"

  # OpenSSL 3.3.1+ fixes macOS CRL (Certificate Revocation List) verification issues
  # that occur with OpenSSL 3.6 + Ruby (certificate verify failed: unable to get certificate CRL).
  # See: https://github.com/ruby/openssl/issues/949
  # This dependency may be removable in future Ruby versions once the fix is widely available.
  spec.add_runtime_dependency "openssl", "~> 3.3.1"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "appraisal", "~> 2.5"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "kramdown", "~> 2.0"
end
