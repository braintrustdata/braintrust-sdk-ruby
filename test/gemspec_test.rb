# frozen_string_literal: true

require "test_helper"

# Guards what ships in the published gem. Files that exist in the repo but are
# missing from the gemspec fail only at runtime, in a customer's app.
class GemspecTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Repo files under lib/ that are intentionally not packaged.
  UNPACKAGED = [
    "lib/braintrust/eval/.eval-design.md" # internal design note
  ].freeze

  def setup
    @spec = Gem::Specification.load(File.join(ROOT, "braintrust.gemspec"))
  end

  def test_packages_rails_generator_template
    assert_includes @spec.files,
      "lib/braintrust/contrib/rails/server/templates/initializer.rb.tt",
      "The Rails server generator cannot create config/initializers/braintrust_server.rb " \
      "without its template."
  end

  def test_packages_every_runtime_file_under_lib
    missing = tracked_lib_files - @spec.files - UNPACKAGED

    assert_empty missing,
      "These lib/ files are in the repo but not in the gem. Add them to " \
      "braintrust.gemspec, or to GemspecTest::UNPACKAGED if they are not runtime files."
  end

  # The gemspec globs all of lib/, so anything sitting in the working tree gets
  # packaged. Releases build from a clean checkout, but a local `rake build`
  # would otherwise quietly ship untracked scratch files.
  def test_packages_nothing_untracked_from_lib
    packaged_from_lib = @spec.files.select { |path| path.start_with?("lib/") }

    assert_empty packaged_from_lib - tracked_lib_files,
      "These files would ship in the gem but are not tracked by git."
  end

  def tracked_lib_files
    files = Dir.chdir(ROOT) { `git ls-files lib`.split("\n") }
    skip "not a git checkout" if files.empty?
    files
  end

  def test_packages_no_directories
    directories = @spec.files.reject { |path| File.file?(File.join(ROOT, path)) }

    assert_empty directories, "spec.files must list files, not directories."
  end
end
