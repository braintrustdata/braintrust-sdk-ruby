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

desc "Run linter with auto-fix"
task :"lint:fix" do
  sh "bundle exec standardrb --fix"
end

desc "Remove Ruby build artifacts"
task :clean do
  FileUtils.rm_rf("pkg")
  FileUtils.rm_rf("coverage")
  FileUtils.rm_rf("doc")
  FileUtils.rm_rf(".yardoc")
  FileUtils.rm_rf("tmp")
  FileUtils.rm_f(Dir.glob("*.gem"))
  FileUtils.rm_f("changelog.md")
end

def run_example(example)
  prefix = case example
  when /openai/, /kitchen-sink/
    "bundle exec appraisal openai-latest"
  else
    "bundle exec"
  end

  sh "#{prefix} ruby #{example}"
end

desc "Run a single example with the correct gemfile"
task :example, [:path] do |t, args|
  example = args[:path]
  raise "Usage: rake example[path/to/example.rb]" unless example

  puts "Running #{example}..."
  run_example(example)
end

desc "Run all examples"
task :examples do
  examples = FileList["examples/**/*.rb"].exclude("examples/**/README.md")

  puts "Running #{examples.length} examples..."

  examples.each do |example|
    puts "\n=== Running #{example} ==="
    run_example(example)
  end
end

desc "Build the gem"
task build: [:clean] do
  sh "gem build braintrust.gemspec"
end

desc "Generate YARD documentation"
task :yard do
  sh "bundle exec yard doc"
end

desc "Run tests and open coverage report"
task coverage: :test do
  coverage_file = "coverage/index.html"

  case RbConfig::CONFIG["host_os"]
  when /darwin/i
    sh "open #{coverage_file}"
  when /linux/i
    sh "xdg-open #{coverage_file}"
  when /mswin|mingw|cygwin/i
    sh "start #{coverage_file}"
  else
    puts "Coverage report available at: #{File.expand_path(coverage_file)}"
  end
end

desc "Verify CI (lint + test all appraisal scenarios)"
task ci: [:lint, :"test:appraisal:install", :"test:appraisal"]

task default: :ci

# Test-related tasks
namespace :test do
  desc "Run tests with verbose timing output"
  task :verbose do
    ENV["MT_VERBOSE"] = "1"
    Rake::Task[:test].invoke
  end

  desc "Install optional test dependencies (e.g., openai gem)"
  task :install do
    puts "Installing optional test dependencies..."
    sh "gem install openai -v '~> 0.34'"
    puts "✓ Optional dependencies installed"
    puts ""
    puts "Now run 'rake test' to run tests with OpenAI integration"
  end

  # Appraisal tasks for testing with/without optional dependencies
  # Run directly: bundle exec appraisal [scenario] rake test
  # List scenarios: bundle exec appraisal list
  desc "Run tests against different dependencies"
  task :appraisal do
    sh "bundle exec appraisal rake test"
  end

  desc "Run tests against all dependency scenarios (alias for test:appraisal)"
  task all: :appraisal

  namespace :appraisal do
    desc "Show help for appraisal scenarios and usage"
    task :help do
      puts "\n=== Appraisal Test Scenarios ==="
      puts "\nAvailable scenarios:"
      sh "bundle exec appraisal list"
      puts "\n=== Usage ==="
      puts "Run specific scenario:"
      puts "  bundle exec appraisal <scenario> rake test"
      puts ""
      puts "Example:"
      puts "  bundle exec appraisal openai-0.34 rake test"
      puts ""
      puts "Run all scenarios:"
      puts "  bundle exec appraisal rake test"
      puts "  or: rake test:appraisal"
      puts ""
    end

    desc "Install all appraisal gemfiles"
    task :install do
      sh "bundle exec appraisal install"
    end
  end

  # VCR tasks for managing HTTP cassettes
  namespace :vcr do
    desc "Re-record all VCR cassettes"
    task :record_all do
      ENV["VCR_MODE"] = "all"
      Rake::Task["test"].invoke
    end

    desc "Record new VCR cassettes only"
    task :record_new do
      ENV["VCR_MODE"] = "new_episodes"
      Rake::Task["test"].invoke
    end

    desc "Run tests without VCR"
    task :off do
      ENV["VCR_OFF"] = "true"
      Rake::Task["test"].invoke
    end
  end
end

# Release tasks
namespace :release do
  task :validate do
    sh "bash scripts/validate-release-tag.sh"
  end

  task publish: ["release:validate", :lint, :build] do
    gem_files = FileList["braintrust-*.gem"]
    if gem_files.empty?
      puts "Error: No gem file found. Build task should have created it."
      exit 1
    elsif gem_files.length > 1
      puts "Error: Multiple gem files found. Clean task should have removed them."
      puts "Found: #{gem_files.join(", ")}"
      exit 1
    end
    sh "gem push #{gem_files.first}"
    puts "✓ Gem pushed to RubyGems"
  end

  task :changelog do
    sh "bash scripts/generate-release-notes.sh > changelog.md"
    puts "✓ Changelog generated: changelog.md"
  end

  task github: [:changelog] do
    require_relative "lib/braintrust/version"
    tag = "v#{Braintrust::VERSION}"

    sh "gh release create #{tag} --title 'Release #{tag}' --notes-file changelog.md"
    puts "✓ GitHub release created: #{tag}"
  end

  task :prerelease do
    # Get current version
    require_relative "lib/braintrust/version"
    original_version = Braintrust::VERSION

    # Generate prerelease version with GitHub run number or timestamp
    run_number = ENV["GITHUB_RUN_NUMBER"] || Time.now.to_i.to_s
    prerelease_version = "#{original_version}.alpha.#{run_number}"

    puts "Original version: #{original_version}"
    puts "Prerelease version: #{prerelease_version}"

    # Temporarily modify version.rb
    version_file = "lib/braintrust/version.rb"
    content = File.read(version_file)
    modified_content = content.gsub(
      /VERSION = "#{Regexp.escape(original_version)}"/,
      "VERSION = \"#{prerelease_version}\""
    )

    File.write(version_file, modified_content)

    begin
      # Build and publish
      Rake::Task["build"].invoke
      Rake::Task["release:publish"].invoke
      puts "✓ Prerelease #{prerelease_version} published successfully!"
    ensure
      # Restore original version
      File.write(version_file, content)
      puts "Restored original version.rb"
    end
  end
end

task release: ["release:publish", "release:github"] do
  puts "✓ Release completed successfully!"
end
