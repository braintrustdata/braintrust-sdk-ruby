# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

BRAINTRUST_CONFIG_ENV_VALUES = {
  "BRAINTRUST_API_KEY" => ENV["BRAINTRUST_API_KEY"],
  "BRAINTRUST_ORG_NAME" => ENV["BRAINTRUST_ORG_NAME"],
  "BRAINTRUST_APP_URL" => ENV["BRAINTRUST_APP_URL"],
  "BRAINTRUST_API_URL" => ENV["BRAINTRUST_API_URL"]
}.freeze

class Braintrust::ConfigTest < Minitest::Test
  def setup
    # Setup a clean state
    BRAINTRUST_CONFIG_ENV_VALUES.keys.each { |env_var| ENV.delete(env_var) }
    @original_cwd = Dir.pwd
    @tmpdir = Dir.mktmpdir("braintrust-config-test")
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@original_cwd)
    FileUtils.rm_rf(@tmpdir)

    # Restore original env vars
    BRAINTRUST_CONFIG_ENV_VALUES.each do |env_var, env_value|
      if env_value
        ENV[env_var] = env_value
      else
        ENV.delete(env_var)
      end
    end
  end

  def test_parses_api_key_from_env
    ENV["BRAINTRUST_API_KEY"] = "test-key-123"

    config = Braintrust::Config.from_env

    assert_equal "test-key-123", config.api_key
  end

  def test_provides_default_values
    config = Braintrust::Config.from_env

    assert_equal "https://www.braintrust.dev", config.app_url
    assert_equal "https://api.braintrust.dev", config.api_url
  end

  def test_passed_options_override_env_vars
    ENV["BRAINTRUST_API_KEY"] = "env-key"
    ENV["BRAINTRUST_ORG_NAME"] = "env-org"

    config = Braintrust::Config.from_env(
      api_key: "explicit-key",
      org_name: "explicit-org"
    )

    assert_equal "explicit-key", config.api_key
    assert_equal "explicit-org", config.org_name
  end

  def test_env_vars_override_defaults
    ENV["BRAINTRUST_APP_URL"] = "https://custom.braintrust.dev"

    config = Braintrust::Config.from_env

    assert_equal "https://custom.braintrust.dev", config.app_url
  end

  def test_falls_back_to_env_braintrust_file
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n")

    config = Braintrust::Config.from_env

    assert_equal "file-key", config.api_key
  end

  def test_env_braintrust_lookup_uses_cwd_from_api_key_lookup
    config = Braintrust::Config.from_env
    other_dir = File.join(@tmpdir, "other")
    FileUtils.mkdir_p(other_dir)
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n", dir: other_dir)

    Dir.chdir(other_dir)

    assert_equal "file-key", config.api_key
  end

  def test_falls_back_to_env_braintrust_when_process_env_is_blank
    ENV["BRAINTRUST_API_KEY"] = "   "
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n")

    config = Braintrust::Config.from_env

    assert_equal "file-key", config.api_key
  end

  def test_process_env_overrides_env_braintrust
    ENV["BRAINTRUST_API_KEY"] = "env-key"
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n")

    config = Braintrust::Config.from_env

    assert_equal "env-key", config.api_key
  end

  def test_explicit_api_key_overrides_env_and_env_braintrust
    ENV["BRAINTRUST_API_KEY"] = "env-key"
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n")

    config = Braintrust::Config.from_env(api_key: "explicit-key")

    assert_equal "explicit-key", config.api_key
  end

  def test_finds_nearest_parent_env_braintrust
    nested = File.join(@tmpdir, "packages", "app")
    FileUtils.mkdir_p(nested)
    write_braintrust_env("BRAINTRUST_API_KEY=root-key\n")
    write_braintrust_env("BRAINTRUST_API_KEY=package-key\n", dir: File.dirname(nested))

    Dir.chdir(nested)
    config = Braintrust::Config.from_env

    assert_equal "package-key", config.api_key
  end

  def test_nearest_env_braintrust_without_key_is_boundary
    nested = File.join(@tmpdir, "packages", "app")
    package_dir = File.dirname(nested)
    FileUtils.mkdir_p(nested)
    write_braintrust_env("BRAINTRUST_API_KEY=root-key\n")
    write_braintrust_env("OTHER=value\n", dir: package_dir)

    Dir.chdir(nested)
    config = Braintrust::Config.from_env

    assert_nil config.api_key
  end

  def test_nearest_env_braintrust_with_blank_key_is_boundary
    nested = File.join(@tmpdir, "packages", "app")
    package_dir = File.dirname(nested)
    FileUtils.mkdir_p(nested)
    write_braintrust_env("BRAINTRUST_API_KEY=root-key\n")
    write_braintrust_env("BRAINTRUST_API_KEY=\"   \"\n", dir: package_dir)

    Dir.chdir(nested)
    config = Braintrust::Config.from_env

    assert_nil config.api_key
  end

  def test_unreadable_nearest_env_braintrust_is_boundary
    nested = File.join(@tmpdir, "packages", "app")
    package_dir = File.dirname(nested)
    FileUtils.mkdir_p(nested)
    write_braintrust_env("BRAINTRUST_API_KEY=root-key\n")
    FileUtils.mkdir_p(File.join(package_dir, ".env.braintrust"))

    Dir.chdir(nested)
    config = Braintrust::Config.from_env

    assert_nil config.api_key
  end

  def test_searches_cwd_and_at_most_64_parents
    segments = Array.new(65) { |i| "d#{i}" }
    nested = File.join(@tmpdir, *segments)
    FileUtils.mkdir_p(nested)
    write_braintrust_env("BRAINTRUST_API_KEY=too-high\n")

    Dir.chdir(nested)
    assert_nil Braintrust::Config.from_env.api_key

    write_braintrust_env("BRAINTRUST_API_KEY=boundary-key\n", dir: File.join(@tmpdir, segments.first))

    assert_equal "boundary-key", Braintrust::Config.from_env.api_key
  end

  def test_supports_dotenv_syntax_without_loading_other_variables
    write_braintrust_env("export BRAINTRUST_API_KEY=\"quoted-key\" # comment\nOTHER=value\n")

    config = Braintrust::Config.from_env

    assert_equal "quoted-key", config.api_key
    assert_nil ENV["OTHER"]
  end

  def test_does_not_mutate_process_env
    write_braintrust_env("BRAINTRUST_API_KEY=file-key\n")

    config = Braintrust::Config.from_env

    assert_equal "file-key", config.api_key
    assert_nil ENV["BRAINTRUST_API_KEY"]
  end

  private

  def write_braintrust_env(contents, dir: @tmpdir)
    File.write(File.join(dir, ".env.braintrust"), contents)
  end
end
