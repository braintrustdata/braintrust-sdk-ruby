# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Run Standard linter"
task :lint do
  sh "bundle exec standardrb"
end

desc "Run Standard linter with auto-fix"
task :"lint:fix" do
  sh "bundle exec standardrb --fix"
end

desc "Remove all ignored files (coverage, pkg, etc.)"
task :clean do
  sh "git clean -fdX"
end

desc "Run all examples"
task :examples do
  examples = FileList["examples/**/*.rb"].exclude("examples/**/README.md")

  puts "Running #{examples.length} examples..."

  examples.each do |example|
    puts "\n=== Running #{example} ==="
    sh "bundle exec ruby #{example}" do |ok, res|
      puts "✓ #{example} completed" if ok
      puts "✗ #{example} failed (#{res.exitstatus})" unless ok
    end
  end
end

desc "Verify CI (lint + test)"
task ci: [:lint, :test]

task default: :ci
