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

desc "Verify CI (lint + test)"
task ci: [:lint, :test]

task default: :ci
