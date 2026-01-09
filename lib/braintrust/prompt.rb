# frozen_string_literal: true

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
    # @param state [State, nil] Braintrust state (default: global)
    # @return [Prompt]
    def self.load(project:, slug:, version: nil, defaults: {}, state: nil)
      state ||= Braintrust.current_state
      raise Error, "No state available - call Braintrust.init first" unless state

      api = API.new(state: state)

      # Find the function by project + slug
      result = api.functions.list(project_name: project, slug: slug)
      function = result.dig("objects")&.first
      raise Error, "Prompt '#{slug}' not found in project '#{project}'" unless function

      # Fetch full function data including prompt_data
      full_data = api.functions.get(id: function["id"])

      new(full_data, defaults: defaults)
    end

    # Initialize a Prompt from function data
    #
    # @param data [Hash] Function data from API
    # @param defaults [Hash] Default variable values for build()
    def initialize(data, defaults: {})
      @data = data
      @defaults = stringify_keys(defaults)

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
      vars = @defaults.merge(stringify_keys(variables_hash)).merge(stringify_keys(kwargs))

      # Substitute variables in messages
      built_messages = messages.map do |msg|
        {
          role: msg["role"].to_sym,
          content: substitute_variables(msg["content"], vars, strict: strict)
        }
      end

      # Build result with model and messages
      result = {
        model: model,
        messages: built_messages
      }

      # Add params (temperature, max_tokens, etc.) to top level
      params = options.dig("params")
      if params.is_a?(Hash)
        params.each do |key, value|
          result[key.to_sym] = value
        end
      end

      result
    end

    private

    # Substitute {{variable}} placeholders with values
    def substitute_variables(text, variables, strict:)
      return text unless text.is_a?(String)

      # Find all {{variable}} patterns
      missing = []

      result = text.gsub(/\{\{([^}]+)\}\}/) do |match|
        var_path = ::Regexp.last_match(1).strip
        value = resolve_variable(var_path, variables)

        if value.nil?
          missing << var_path
          match # Keep original placeholder
        else
          value.to_s
        end
      end

      if strict && missing.any?
        raise Error, "Missing required variables: #{missing.join(", ")}"
      end

      result
    end

    # Resolve a variable path like "user.name" from variables hash
    def resolve_variable(path, variables)
      parts = path.split(".")
      value = variables

      parts.each do |part|
        return nil unless value.is_a?(Hash)
        # Try both string and symbol keys
        value = value[part] || value[part.to_sym]
        return nil if value.nil?
      end

      value
    end

    # Convert hash keys to strings (handles both symbol and string keys)
    def stringify_keys(hash)
      return {} unless hash.is_a?(Hash)

      hash.transform_keys(&:to_s).transform_values do |v|
        v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end
  end
end
