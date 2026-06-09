# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in braintrust.gemspec
gemspec

# Pin openssl to the version bundled with the release runner (Ruby 4.0 ships 4.0.0).
# Keeps the CI lockfile in sync with the runner's default gem to avoid bundler
# activation conflicts. Update this when the ruby-version in release workflows changes.
# Does not affect gem consumers — they use the gemspec constraint (>= 3.3.1).
gem "openssl", "4.0.0"

# Development dependencies
gem "appraisal", "~> 2.5"
gem "climate_control", "~> 1.2"
gem "kramdown", "~> 2.0"
gem "minitest-reporters", "~> 1.6"
gem "minitest-stub-const", "~> 0.6"
gem "minitest", "~> 5.0"
gem "rake", "~> 13.0"
gem "simplecov", "~> 0.22"
gem "standard", "~> 1.0"
gem "vcr", "~> 6.0"
gem "webmock", "~> 3.0"
gem "yard", "~> 0.9"
