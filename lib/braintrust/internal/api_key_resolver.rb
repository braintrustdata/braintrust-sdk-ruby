# frozen_string_literal: true

module Braintrust
  module Internal
    # Resolves the Braintrust API key from explicit options, ENV, or the nearest
    # .env.braintrust file without mutating the process environment.
    class ApiKeyResolver
      ENV_KEY = "BRAINTRUST_API_KEY"
      ENV_FILE = ".env.braintrust"
      SEARCH_PARENT_LIMIT = 64
      ASSIGNMENT_REGEXP = /\A#{Regexp.escape(ENV_KEY)}\s*=\s*(.*)\z/o

      attr_reader :immediate_api_key

      def initialize(explicit_api_key: nil)
        @mutex = Mutex.new
        @resolved = false
        @api_key = nil
        @thread = nil
        @search_start_dir = Dir.pwd

        if !explicit_api_key.nil?
          resolve_immediately(explicit_api_key)
        else
          env_api_key = ENV[ENV_KEY]
          resolve_immediately(env_api_key) if env_api_key && !env_api_key.strip.empty?
        end

        @immediate_api_key = @api_key
      end

      def api_key
        thread = start
        thread&.join

        @mutex.synchronize { @api_key }
      end

      def start
        @mutex.synchronize do
          return nil if @resolved
          return @thread if @thread

          @thread = Thread.new do
            key = self.class.find_file_api_key(@search_start_dir)
            @mutex.synchronize do
              @api_key = key
              @resolved = true
            end
          rescue
            @mutex.synchronize do
              @api_key = nil
              @resolved = true
            end
          end
          @thread.report_on_exception = false
          @thread
        end
      end

      def self.find_file_api_key(start_dir = Dir.pwd)
        dir = start_dir

        0.upto(SEARCH_PARENT_LIMIT) do
          env_path = File.join(dir, ENV_FILE)

          begin
            contents = File.read(env_path)
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
        value = nil

        contents.each_line do |line|
          found, parsed_value = parse_assignment(line)
          value = parsed_value if found
        end

        (value && !value.strip.empty?) ? value : nil
      rescue
        nil
      end

      def self.parse_assignment(line)
        stripped = line.delete_suffix("\n").delete_suffix("\r").lstrip
        return [false, nil] if stripped.empty? || stripped.start_with?("#")

        stripped = stripped.sub(/\Aexport\s+/, "")
        match = stripped.match(ASSIGNMENT_REGEXP)
        return [false, nil] unless match

        [true, parse_value(match[1])]
      end

      def self.parse_value(raw_value)
        value = raw_value.lstrip

        case value[0]
        when '"'
          parse_double_quoted_value(value[1..])
        when "'"
          parse_single_quoted_value(value[1..])
        else
          value.sub(/\s+#.*\z/, "").strip
        end
      end

      def self.parse_double_quoted_value(value)
        parsed = +""
        escaped = false

        value.each_char do |char|
          if escaped
            parsed << case char
            when "n" then "\n"
            when "r" then "\r"
            when "t" then "\t"
            else char
            end
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            return parsed
          else
            parsed << char
          end
        end

        parsed
      end

      def self.parse_single_quoted_value(value)
        quote_index = value.index("'")
        quote_index ? value[0...quote_index] : value
      end

      private_class_method :parse_assignment, :parse_value, :parse_double_quoted_value, :parse_single_quoted_value

      private

      def resolve_immediately(api_key)
        @api_key = api_key
        @resolved = true
      end
    end
  end
end
