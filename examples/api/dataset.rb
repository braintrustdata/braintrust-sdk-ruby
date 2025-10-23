#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using the Braintrust Datasets API
#
# This example demonstrates:
# - Creating a dataset
# - Inserting records
# - Fetching records with pagination
# - Using the low-level API client

require_relative "../../lib/braintrust"

# Initialize Braintrust
Braintrust.init(blocking_login: true)

# Create API client
api = Braintrust::API.new

# Create a new dataset
puts "Creating dataset..."
response = api.datasets.create(
  project_name: "ruby-sdk-examples",
  name: "example-dataset-#{Time.now.to_i}",
  description: "Example dataset created from Ruby SDK"
)

dataset_id = response["dataset"]["id"]
dataset_name = response["dataset"]["name"]
puts "Created dataset: #{dataset_name} (#{dataset_id})"
puts "  Link: #{api.datasets.permalink(id: dataset_id)}"

# Insert some records
puts "\nInserting records..."
events = [
  {input: "hello", expected: "HELLO"},
  {input: "world", expected: "WORLD"},
  {input: "foo", expected: "FOO"},
  {input: "bar", expected: "BAR"}
]

api.datasets.insert(id: dataset_id, events: events)
puts "Inserted #{events.length} records"

# Fetch records back
puts "\nFetching records..."
result = api.datasets.fetch(id: dataset_id, limit: 10)

puts "Retrieved #{result[:records].length} records:"
result[:records].each do |record|
  puts "  - input: #{record["input"]}, expected: #{record["expected"]}"
end

# Fetch by project + name
puts "\nFetching dataset by name..."
metadata = api.datasets.get(project_name: "ruby-sdk-examples", name: dataset_name)
puts "Found dataset: #{metadata["name"]} (#{metadata["id"]})"

# List all datasets in project
puts "\nListing all datasets..."
list_result = api.datasets.list(project_name: "ruby-sdk-examples")
puts "Found #{list_result["objects"].length} datasets in project"

puts "\nDone!"
