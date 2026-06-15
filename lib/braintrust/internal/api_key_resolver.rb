# frozen_string_literal: true

require "json"

module Braintrust
  module Internal
    # Resolves the Braintrust API key from explicit options, ENV, or the nearest
    # .braintrust.json file without mutating the process environment.
    class ApiKeyResolver
      ENV_KEY = "BRAINTRUST_API_KEY"
      CONFIG_FILE = ".braintrust.json"
      SEARCH_PARENT_LIMIT = 64

      def self.resolve(explicit_api_key: nil, start_dir: Dir.pwd)
        return explicit_api_key unless explicit_api_key.nil?

        env_api_key = ENV[ENV_KEY]
        return env_api_key if env_api_key && !env_api_key.strip.empty?

        find_file_api_key(start_dir)
      end

      def self.find_file_api_key(start_dir = Dir.pwd)
        dir = start_dir

        0.upto(SEARCH_PARENT_LIMIT) do
          config_path = File.join(dir, CONFIG_FILE)

          begin
            contents = File.read(config_path)
          rescue Errno::ENOENT, Errno::ENOTDIR
            # Missing candidates are not boundaries; keep walking upward.
          rescue
            return nil
          else
            return parse_api_key(contents)
          end

          parent = File.dirname(dir)
          break if parent == dir
          dir = parent
        end

        nil
      rescue
        nil
      end

      def self.parse_api_key(contents)
        config = JSON.parse(contents)
        return nil unless config.is_a?(Hash)

        value = config[ENV_KEY]
        (value.is_a?(String) && !value.strip.empty?) ? value : nil
      rescue JSON::ParserError, TypeError
        nil
      end

      private_class_method :find_file_api_key, :parse_api_key
    end
  end
end
