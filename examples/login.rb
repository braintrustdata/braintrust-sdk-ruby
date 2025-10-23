#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"

# Basic login example
#
# This example demonstrates how to:
# - Initialize the Braintrust SDK
# - Log in to retrieve organization information
# - Access the state fields after login
#
# Prerequisites:
# - Set BRAINTRUST_API_KEY environment variable
#
# Run with:
#   bundle exec ruby examples/login.rb

# Initialize Braintrust with blocking login
puts "Initializing and logging in to Braintrust..."
state = Braintrust.init(blocking_login: true)

puts "\n✓ Successfully logged in!"
puts "\nOrganization Information:"
puts "  Org ID:       #{state.org_id}"
puts "  Org Name:     #{state.org_name}"
puts "  API URL:      #{state.api_url}"
puts "  Proxy URL:    #{state.proxy_url}"
puts "  Logged In:    #{state.logged_in}"
puts "  App URL:      #{state.app_url}"
