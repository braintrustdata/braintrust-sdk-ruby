# frozen_string_literal: true

require "rake/testtask"

desc "Run tests (optionally with seed: rake test[12345])"
task :test, [:seed] do |t, args|
  seed_opt = args[:seed] ? " -- --seed=#{args[:seed]}" : ""
  sh "ruby -Ilib:test -e \"Dir.glob('test/**/*_test.rb').each { |f| require_relative f }\"#{seed_opt}"
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

def appraisal_for(example)
  case example
  when /ruby_llm/ then "ruby_llm"
  when /ruby-openai/, /ruby_openai/, /alexrudall/ then "ruby-openai"
  when /anthropic/ then "anthropic"
  when /openai/, /kitchen-sink/ then "openai"
  end
end

def run_example(example)
  appraisal = appraisal_for(example)
  prefix = appraisal ? "bundle exec appraisal #{appraisal}" : "bundle exec"
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
task ci: [:lint, :"test:appraisal"]

task default: :ci

# Test-related tasks
namespace :test do
  desc "Run only contrib framework tests"
  task :contrib do
    sh "bundle exec ruby -Ilib:test -e \"Dir.glob('test/braintrust/contrib{_test.rb,/**/*_test.rb}').each { |f| require_relative f }\""
  end

  namespace :contrib do
    # Tasks per integration
    [
      {name: :openai},
      {name: :ruby_llm},
      {name: :ruby_openai, appraisal: "ruby-openai"}
    ].each do |integration|
      name = integration[:name]
      appraisal = integration[:appraisal] || integration[:name]
      folder = integration[:name]

      desc "Run #{name} contrib tests"
      task name do
        sh "bundle exec appraisal #{appraisal} ruby -Ilib:test -e \"Dir.glob('test/braintrust/contrib/#{folder}/**/*_test.rb').each { |f| require_relative f }\""
      end
    end
  end

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
  desc "Run tests against different dependencies (with install)"
  task appraisal: :"appraisal:install" do
    sh "bundle exec appraisal rake test"
  end

  desc "Run tests against all dependency scenarios (without install)"
  task :all do
    sh "bundle exec appraisal rake test"
  end

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

    sh "gh release create #{tag} --title '#{tag}' --notes-file changelog.md"

    # Get the repository URL
    repo = `gh repo view --json nameWithOwner -q .nameWithOwner`.strip
    release_url = "https://github.com/#{repo}/releases/tag/#{tag}"

    puts "✓ GitHub release created: #{tag}"
    puts "  #{release_url}"
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

# Contrib tasks
namespace :contrib do
  desc "Generate a new integration (NAME=name [GEM_NAMES=gem1,gem2] [REQUIRE_PATHS=path1,path2] [MIN_VERSION=1.0.0] [MAX_VERSION=2.0.0] [AUTO_REGISTER=true])"
  task :generate do
    require "erb"
    require "fileutils"

    # Parse parameters
    name = ENV["NAME"]
    unless name
      puts "Error: NAME is required"
      puts "Usage: rake contrib:generate NAME=trustybrain_llm [GEM_NAMES=trustybrain_llm] [AUTO_REGISTER=true]"
      exit 1
    end

    # Convert name to snake_case if it's PascalCase
    snake_case_name = name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase

    # Convert to PascalCase for module name
    module_name = snake_case_name.split("_").map(&:capitalize).join

    integration_name = snake_case_name.to_sym

    # Parse optional parameters
    gem_names = ENV["GEM_NAMES"]&.split(",") || [snake_case_name]
    require_paths = ENV["REQUIRE_PATHS"]&.split(",") || gem_names
    min_version = ENV["MIN_VERSION"]
    max_version = ENV["MAX_VERSION"]
    auto_register = ENV.fetch("AUTO_REGISTER", "false").downcase == "true"

    # Display what will be generated
    puts "\n=== Generating Integration ==="
    puts "Name: #{module_name}"
    puts "Integration name: :#{integration_name}"
    puts "Gem names: #{gem_names.inspect}"
    puts "Require paths: #{require_paths.inspect}" if require_paths != gem_names
    puts "Min version: #{min_version}" if min_version
    puts "Max version: #{max_version}" if max_version
    puts

    # Template binding
    template_binding = binding

    # Paths
    integration_dir = "lib/braintrust/contrib/#{snake_case_name}"
    test_dir = "test/braintrust/contrib/#{snake_case_name}"

    # Create directories
    FileUtils.mkdir_p(integration_dir)
    FileUtils.mkdir_p(test_dir)

    # Generate files
    templates = {
      "templates/contrib/integration.rb.erb" => "#{integration_dir}/integration.rb",
      "templates/contrib/patcher.rb.erb" => "#{integration_dir}/patcher.rb",
      "templates/contrib/integration_test.rb.erb" => "#{test_dir}/integration_test.rb",
      "templates/contrib/patcher_test.rb.erb" => "#{test_dir}/patcher_test.rb"
    }

    templates.each do |template_path, output_path|
      template = ERB.new(File.read(template_path), trim_mode: "-")
      content = template.result(template_binding)
      File.write(output_path, content)
      puts "✓ Created #{output_path}"
    end

    # Auto-register if requested
    if auto_register
      contrib_file = "lib/braintrust/contrib.rb"
      contrib_content = File.read(contrib_file)

      # Find the position to insert (before the last "end" or after the last require)
      insertion_point = if /^# Load integration stubs/.match?(contrib_content)
        contrib_content.index("# Load integration stubs")
      else
        # Insert before the final module end
        contrib_content.rindex("end")
      end

      require_line = "require_relative \"contrib/#{snake_case_name}/integration\""
      register_line = "Contrib::#{module_name}::Integration.register!"

      # Check if already registered
      if contrib_content.include?(require_line)
        puts "⚠ #{contrib_file} already contains this integration"
      else
        lines_to_add = [
          "",
          "# #{module_name}",
          require_line,
          register_line
        ].join("\n")

        contrib_content.insert(insertion_point, lines_to_add + "\n")
        File.write(contrib_file, contrib_content)
        puts "✓ Updated #{contrib_file}"
      end
    end

    # Display next steps
    puts "\n=== Next Steps ==="
    unless auto_register
      puts "1. Add to lib/braintrust/contrib.rb:"
      puts "   require_relative \"contrib/#{snake_case_name}/integration\""
      puts "   Contrib::#{module_name}::Integration.register!"
      puts
    end
    puts "#{auto_register ? "1" : "2"}. Implement the patcher in:"
    puts "   #{integration_dir}/patcher.rb"
    puts
    puts "#{auto_register ? "2" : "3"}. Add tests in:"
    puts "   #{test_dir}/"
    puts
    puts "#{auto_register ? "3" : "4"}. Run tests:"
    puts "   bundle exec rake test TEST=#{test_dir}/**/*_test.rb"
    puts
  end
end

# Version bump tasks
def bump_version(type)
  version_file = "lib/braintrust/version.rb"
  content = File.read(version_file)
  current = content.match(/VERSION = "(\d+)\.(\d+)\.(\d+)"/)
  raise "Could not parse version from #{version_file}" unless current

  major, minor, patch = current[1].to_i, current[2].to_i, current[3].to_i
  old_version = "#{major}.#{minor}.#{patch}"

  case type
  when :major
    major += 1
    minor = 0
    patch = 0
  when :minor
    minor += 1
    patch = 0
  when :patch
    patch += 1
  end

  new_version = "#{major}.#{minor}.#{patch}"
  new_content = content.gsub(/VERSION = "#{old_version}"/, "VERSION = \"#{new_version}\"")
  File.write(version_file, new_content)

  puts "#{old_version} → #{new_version}"
  new_version
end

namespace :version do
  namespace :bump do
    desc "Bump patch version (0.0.5 → 0.0.6)"
    task :patch do
      bump_version(:patch)
    end

    desc "Bump minor version (0.0.5 → 0.1.0)"
    task :minor do
      bump_version(:minor)
    end

    desc "Bump major version (0.0.5 → 1.0.0)"
    task :major do
      bump_version(:major)
    end
  end
end
