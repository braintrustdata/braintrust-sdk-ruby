# Milestone 06: CLI Wrapper

## Goal

Zero-code instrumentation via command line wrapper.

## What You Get

Instrument any Ruby application without code changes:

```bash
# Basic usage
braintrust exec -- ruby app.rb

# With Rails
braintrust exec -- bundle exec rails server

# With filtering
braintrust exec --only openai,anthropic -- ruby app.rb
braintrust exec --except ruby_llm -- ruby app.rb
```

## Success Criteria

- `braintrust exec -- COMMAND` instruments the application
- `--only` flag filters to specific integrations
- `--except` flag excludes specific integrations
- Works with any Ruby command (ruby, bundle exec, rails, rake, etc.)
- Preserves existing `RUBYOPT` settings

## Files to Create

### `exe/braintrust`

```ruby
#!/usr/bin/env ruby
# exe/braintrust

require "optparse"

module Braintrust
  module CLI
    class << self
      def run(args)
        command = parse_args(args)
        case command
        when :exec
          exec_command
        when :help
          print_help
        else
          print_help
          exit 1
        end
      end

      private

      def parse_args(args)
        @options = {}
        @remaining_args = []

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: braintrust <command> [options]"

          opts.separator ""
          opts.separator "Commands:"
          opts.separator "  exec    Run a command with auto-instrumentation"
          opts.separator ""
          opts.separator "Options:"

          opts.on("--only INTEGRATIONS", "Only instrument these (comma-separated)") do |v|
            @options[:only] = v
          end

          opts.on("--except INTEGRATIONS", "Skip these integrations (comma-separated)") do |v|
            @options[:except] = v
          end

          opts.on("-h", "--help", "Show this help") do
            @options[:help] = true
          end

          opts.on("-v", "--version", "Show version") do
            require "braintrust/version"
            puts "braintrust #{Braintrust::VERSION}"
            exit 0
          end
        end

        # Parse up to "--" separator
        separator_index = args.index("--")
        if separator_index
          to_parse = args[0...separator_index]
          @remaining_args = args[(separator_index + 1)..]
        else
          to_parse = args
        end

        parser.parse!(to_parse)

        return :help if @options[:help] || to_parse.empty?
        return to_parse.first.to_sym
      rescue OptionParser::InvalidOption => e
        puts e.message
        print_help
        exit 1
      end

      def exec_command
        if @remaining_args.empty?
          puts "Error: No command specified after --"
          puts "Usage: braintrust exec [options] -- COMMAND"
          exit 1
        end

        # Set environment variables for auto_instrument
        ENV["BRAINTRUST_INSTRUMENT_ONLY"] = @options[:only] if @options[:only]
        ENV["BRAINTRUST_INSTRUMENT_EXCEPT"] = @options[:except] if @options[:except]

        # Inject auto-instrument via RUBYOPT
        rubyopt = ENV["RUBYOPT"] || ""
        ENV["RUBYOPT"] = "#{rubyopt} -rbraintrust/contrib/auto_instrument".strip

        # Execute the command (replaces current process)
        exec(*@remaining_args)
      end

      def print_help
        puts <<~HELP
          Braintrust CLI - Auto-instrument Ruby applications

          Usage:
            braintrust exec [options] -- COMMAND

          Commands:
            exec    Run a command with auto-instrumentation enabled

          Options:
            --only INTEGRATIONS     Only instrument these (comma-separated)
            --except INTEGRATIONS   Skip these integrations (comma-separated)
            -h, --help              Show this help
            -v, --version           Show version

          Examples:
            braintrust exec -- ruby app.rb
            braintrust exec -- bundle exec rails server
            braintrust exec --only openai -- ruby app.rb
            braintrust exec --except ruby_llm -- bundle exec rake

          Environment Variables:
            BRAINTRUST_API_KEY              API key for Braintrust
            BRAINTRUST_INSTRUMENT_ONLY      Comma-separated whitelist
            BRAINTRUST_INSTRUMENT_EXCEPT    Comma-separated blacklist
        HELP
      end
    end
  end
end

Braintrust::CLI.run(ARGV)
```

## Files to Modify

### `braintrust.gemspec`

Add executable:

```ruby
Gem::Specification.new do |spec|
  # ... existing config ...

  spec.executables = ["braintrust"]

  # ... rest of config ...
end
```

## How It Works

1. Parse command-line options (`--only`, `--except`)
2. Set environment variables for filtering
3. Inject `-rbraintrust/contrib/auto_instrument` into `RUBYOPT`
4. `exec` the user's command (replaces current process)
5. When Ruby starts, it loads `auto_instrument.rb` before the app
6. Auto-instrument sets up require hooks and patches available libraries

## Tests to Create

### `test/braintrust/cli_test.rb`

- Test option parsing (`--only`, `--except`)
- Test RUBYOPT injection
- Test environment variable passthrough
- Test error handling (no command specified)
- Test `--help` and `--version`

### Integration test

- Actually run `braintrust exec -- ruby -e "..."` and verify instrumentation works

## Documentation

Update README:
- Add "CLI Usage" section
- Show examples for common scenarios (Rails, plain Ruby, etc.)

## Potential Challenges

| Challenge | Mitigation |
|-----------|------------|
| Existing RUBYOPT conflicts | Append to existing RUBYOPT, don't replace |
| Cross-platform issues | Test on Linux, macOS, Windows |
| Bundler with `--path` | May need to ensure gem is in load path |

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [05-require-time-auto-instrument.md](05-require-time-auto-instrument.md) must be complete
