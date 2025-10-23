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

# Release tasks
namespace :release do
  desc "Validate release tag and version"
  task :validate do
    sh "bash scripts/validate-release-tag.sh"
  end

  desc "Build the gem"
  task build: [:clean] do
    sh "gem build braintrust.gemspec"
  end

  desc "Publish gem to RubyGems (requires authentication)"
  task :publish do
    gem_file = FileList["braintrust-*.gem"].first
    unless gem_file
      puts "Error: No gem file found. Run 'rake release:build' first."
      exit 1
    end
    sh "gem push #{gem_file}"
  end

  desc "Generate changelog for release"
  task :changelog do
    sh "bash scripts/generate-release-notes.sh > changelog.md"
    puts "✓ Changelog generated: changelog.md"
  end

  desc "Create GitHub release"
  task :github do
    unless File.exist?("changelog.md")
      puts "Error: changelog.md not found. Run 'rake release:changelog' first."
      exit 1
    end

    require_relative "lib/braintrust/version"
    tag = "v#{Braintrust::VERSION}"

    sh "gh release create #{tag} --title 'Release #{tag}' --notes-file changelog.md"
    puts "✓ GitHub release created: #{tag}"
  end

  desc "Build and publish prerelease (modifies version with alpha suffix)"
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
      Rake::Task["release:build"].invoke
      Rake::Task["release:publish"].invoke
      puts "✓ Prerelease #{prerelease_version} published successfully!"
    ensure
      # Restore original version
      File.write(version_file, content)
      puts "Restored original version.rb"
    end
  end
end

desc "Full release: validate, lint, generate changelog, build, publish, and create GitHub release"
task release: ["release:validate", :lint, "release:changelog", "release:build", "release:publish", "release:github"] do
  puts "✓ Release completed successfully!"
end
