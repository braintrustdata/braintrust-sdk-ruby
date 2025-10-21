# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "braintrust"

require "minitest/autorun"
require "simplecov"

SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
  minimum_coverage 80
end
