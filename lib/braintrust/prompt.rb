# frozen_string_literal: true

require "json"
require_relative "internal/template"

module Braintrust
  # Prompt class for loading and building prompts from Braintrust
  #
  # @example Load and use a prompt
  #   prompt = Braintrust::Prompt.load(project: "my-project", slug: "summarizer")
  #   params = prompt.build(text: "Article to summarize...")
  #   client.messages.create(**params)
  class Prompt
    attr_reader :id, :name, :slug, :project_id

    # Load a prompt from Braintrust
    #
    # @param project [String] Project name
    # @param slug [String] Prompt slug
    # @param version [String, nil] Specific version (default: latest)
    # @param defaults [Hash] Default variable values for build()
    # @param api [API, nil] Braintrust API client (default: creates one using global state)
    # @return [Prompt]
    def self.load(project:, slug:, version: nil, defaults: {}, api: nil)
      api ||= API.new

      # Find the function by project + slug
      result = api.functions.list(project_name: project, slug: slug)
      function = result.dig("objects")&.first
      raise Error, "Prompt '#{slug}' not found in project '#{project}'" unless function

      # Fetch full function data including prompt_data
      full_data = api.functions.get(id: function["id"], version: version)

      new(full_data, defaults: defaults)
    end

    # Initialize a Prompt from function data
    #
    # @param data [Hash] Function data from API
    # @param defaults [Hash] Default variable values for build()
    def initialize(data, defaults: {})
      @data = data
      @defaults = Internal::Template.stringify_keys(defaults)

      @id = data["id"]
      @name = data["name"]
      @slug = data["slug"]
      @project_id = data["project_id"]
    end

    # Get the raw prompt definition
    # @return [Hash, nil]
    def prompt
      @data.dig("prompt_data", "prompt")
    end

    # Get the prompt messages
    # @return [Array<Hash>]
    def messages
      prompt&.dig("messages") || []
    end

    # Get the tools definition (parsed from JSON string)
    # @return [Array<Hash>, nil]
    def tools
      tools_json = prompt&.dig("tools")
      return nil unless tools_json.is_a?(String) && !tools_json.empty?

      JSON.parse(tools_json)
    rescue JSON::ParserError
      nil
    end

    # Get the model name
    # @return [String, nil]
    def model
      @data.dig("prompt_data", "options", "model")
    end

    # Get model options
    # @return [Hash]
    def options
      @data.dig("prompt_data", "options") || {}
    end

    # Get the template format
    # @return [String] "mustache" (default), "nunjucks", or "none"
    def template_format
      @data.dig("prompt_data", "template_format") || "mustache"
    end

    # Build the prompt with variable substitution
    #
    # Returns a hash ready to pass to an LLM client:
    #   {model: "...", messages: [...], temperature: ..., ...}
    #
    # @param variables [Hash] Variables to substitute (e.g., {name: "Alice"})
    # @param strict [Boolean] Raise error on missing variables (default: false)
    # @return [Hash] Built prompt ready for LLM client
    #
    # @example With keyword arguments
    #   prompt.build(name: "Alice", task: "coding")
    #
    # @example With explicit hash
    #   prompt.build({name: "Alice"}, strict: true)
    def build(variables = nil, strict: false, **kwargs)
      # Support both explicit hash and keyword arguments
      variables_hash = variables.is_a?(Hash) ? variables : {}
      vars = @defaults
        .merge(Internal::Template.stringify_keys(variables_hash))
        .merge(Internal::Template.stringify_keys(kwargs))

      # Render Mustache templates in messages
      built_messages = messages.map do |msg|
        {
          role: msg["role"].to_sym,
          content: Internal::Template.render(msg["content"], vars, format: template_format, strict: strict)
        }
      end

      # Build result with model and messages
      result = {
        model: model,
        messages: built_messages
      }

      # Add tools if defined
      parsed_tools = tools
      result[:tools] = parsed_tools if parsed_tools

      # Add params (temperature, max_tokens, etc.) to top level
      params = options.dig("params")
      if params.is_a?(Hash)
        params.each do |key, value|
          result[key.to_sym] = value
        end
      end

      result
    end
  end
end
