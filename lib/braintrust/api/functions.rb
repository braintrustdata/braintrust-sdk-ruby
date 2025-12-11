# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  class API
    # Functions API namespace
    # Provides methods for creating, invoking, and managing remote functions (prompts)
    class Functions
      TYPE_LLM = "llm"
      TYPE_PROMPT = "prompt"
      TYPE_SCORER = "scorer"
      TYPE_TASK = "task"
      TYPE_TOOL = "tool"

      def initialize(api)
        @api = api
        @state = api.state
      end

      # List functions with optional filters
      # GET /v1/function?project_name=X&...
      # @param project_name [String, nil] Filter by project name
      # @param function_name [String, nil] Filter by function name
      # @param slug [String, nil] Filter by slug
      # @param limit [Integer, nil] Limit number of results
      # @return [Hash] Response with "objects" array
      def list(project_name: nil, function_name: nil, slug: nil, limit: nil)
        params = {}
        params["project_name"] = project_name if project_name
        params["function_name"] = function_name if function_name
        params["slug"] = slug if slug
        params["limit"] = limit if limit

        http_get("/v1/function", params)
      end

      # Create or register a function (idempotent)
      # POST /v1/function
      # This method is idempotent - if a function with the same slug already exists in the project,
      # it will return the existing function unmodified. Unlike datasets, the response does not
      # include a "found_existing" field.
      # @param project_name [String] Project name
      # @param slug [String] Function slug (URL-friendly identifier)
      # @param function_data [Hash] Function configuration (usually {type: "prompt"})
      # @param prompt_data [Hash, nil] Prompt configuration (prompt, options, etc.)
      # @param name [String, nil] Optional display name (defaults to slug)
      # @param description [String, nil] Optional description
      # @param function_type [String, nil] Function type ("llm", "scorer", "task", "tool", or nil)
      # @param function_schema [Hash, nil] JSON schema for function parameters and return type
      #   @option function_schema [Hash] :parameters JSON schema for input parameters
      #   @option function_schema [Hash] :returns JSON schema for return value
      # @return [Hash] Function metadata
      def create(project_name:, slug:, function_data:, prompt_data: nil, name: nil, description: nil, function_type: nil, function_schema: nil)
        # Look up project ID
        projects_result = http_get("/v1/project", {"project_name" => project_name})
        project = projects_result["objects"]&.first
        raise Error, "Project '#{project_name}' not found" unless project
        project_id = project["id"]

        payload = {
          project_id: project_id,
          slug: slug,
          name: name || slug,  # Name is required, default to slug
          function_data: function_data
        }
        payload[:prompt_data] = prompt_data if prompt_data
        payload[:description] = description if description
        payload[:function_type] = function_type if function_type
        payload[:function_schema] = function_schema if function_schema

        http_post_json("/v1/function", payload)
      end

      # Invoke a function by ID with input
      # POST /v1/function/{id}/invoke
      # @param id [String] Function UUID
      # @param input [Object] Input data to pass to the function
      # @return [Object] The function output (String, Hash, Array, etc.) as returned by the HTTP API
      def invoke(id:, input:)
        payload = {input: input}
        http_post_json("/v1/function/#{id}/invoke", payload)
      end

      # Delete a function by ID
      # DELETE /v1/function/{id}
      # @param id [String] Function UUID
      # @return [Hash] Delete response
      def delete(id:)
        http_delete("/v1/function/#{id}")
      end

      # Create a tool function
      # Tools are functions that LLMs can call during execution.
      # @param project_name [String] Project name
      # @param slug [String] Function slug (URL-friendly identifier)
      # @param prompt_data [Hash] Prompt configuration (prompt, options, etc.)
      # @param name [String, nil] Optional display name (defaults to slug)
      # @param description [String, nil] Description of what the tool does (recommended for LLM understanding)
      # @param function_schema [Hash, nil] JSON schema defining the tool's parameters and return type
      # @return [Hash] Function metadata
      def create_tool(project_name:, slug:, prompt_data:, name: nil, description: nil, function_schema: nil)
        validate_prompt_data!(prompt_data)
        create(
          project_name: project_name,
          slug: slug,
          function_data: {type: TYPE_PROMPT},
          prompt_data: prompt_data,
          name: name,
          description: description,
          function_type: TYPE_TOOL,
          function_schema: function_schema
        )
      end

      # Create a scorer function
      # Scorers evaluate task outputs and return scores (typically 0-1).
      # @param project_name [String] Project name
      # @param slug [String] Function slug (URL-friendly identifier)
      # @param prompt_data [Hash] Prompt configuration for the scoring logic
      # @param name [String, nil] Optional display name (defaults to slug)
      # @param description [String, nil] Optional description
      # @param function_schema [Hash, nil] JSON schema for parameters and return type
      # @return [Hash] Function metadata
      def create_scorer(project_name:, slug:, prompt_data:, name: nil, description: nil, function_schema: nil)
        validate_prompt_data!(prompt_data)
        create(
          project_name: project_name,
          slug: slug,
          function_data: {type: TYPE_PROMPT},
          prompt_data: prompt_data,
          name: name,
          description: description,
          function_type: TYPE_SCORER,
          function_schema: function_schema
        )
      end

      # Create a task function
      # Tasks are general-purpose prompt functions.
      # @param project_name [String] Project name
      # @param slug [String] Function slug (URL-friendly identifier)
      # @param prompt_data [Hash] Prompt configuration (prompt, options, etc.)
      # @param name [String, nil] Optional display name (defaults to slug)
      # @param description [String, nil] Optional description
      # @param function_schema [Hash, nil] JSON schema for parameters and return type
      # @return [Hash] Function metadata
      def create_task(project_name:, slug:, prompt_data:, name: nil, description: nil, function_schema: nil)
        validate_prompt_data!(prompt_data)
        create(
          project_name: project_name,
          slug: slug,
          function_data: {type: TYPE_PROMPT},
          prompt_data: prompt_data,
          name: name,
          description: description,
          function_type: TYPE_TASK,
          function_schema: function_schema
        )
      end

      # Create an LLM function
      # LLM functions are prompt-based functions categorized as LLM type.
      # @param project_name [String] Project name
      # @param slug [String] Function slug (URL-friendly identifier)
      # @param prompt_data [Hash] Prompt configuration (prompt, options, etc.)
      # @param name [String, nil] Optional display name (defaults to slug)
      # @param description [String, nil] Optional description
      # @param function_schema [Hash, nil] JSON schema for parameters and return type
      # @return [Hash] Function metadata
      def create_llm(project_name:, slug:, prompt_data:, name: nil, description: nil, function_schema: nil)
        validate_prompt_data!(prompt_data)
        create(
          project_name: project_name,
          slug: slug,
          function_data: {type: TYPE_PROMPT},
          prompt_data: prompt_data,
          name: name,
          description: description,
          function_type: TYPE_LLM,
          function_schema: function_schema
        )
      end

      private

      # Validate prompt_data structure
      # @param prompt_data [Hash] The prompt data to validate
      # @raise [ArgumentError] If prompt_data is invalid
      def validate_prompt_data!(prompt_data)
        raise ArgumentError, "prompt_data must be a Hash" unless prompt_data.is_a?(Hash)

        has_prompt = prompt_data.key?(:prompt) || prompt_data.key?(TYPE_PROMPT)
        raise ArgumentError, "prompt_data must contain a :prompt key" unless has_prompt
      end

      # Core HTTP request method with logging
      # @param method [Symbol] :get, :post, or :delete
      # @param path [String] API path
      # @param params [Hash] Query params (for GET)
      # @param payload [Hash, nil] JSON payload (for POST)
      # @param parse_json [Boolean] Whether to parse response as JSON (default: true)
      # @return [Hash, Net::HTTPResponse] Parsed JSON or raw response
      def http_request(method, path, params: {}, payload: nil, parse_json: true)
        # Build URI
        base = @state.api_url
        uri = URI("#{base}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        # Create request
        request = case method
        when :get
          Net::HTTP::Get.new(uri)
        when :post
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = JSON.dump(payload) if payload
          req
        when :delete
          Net::HTTP::Delete.new(uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        request["Authorization"] = "Bearer #{@state.api_key}"

        # Execute request with timing
        start_time = Time.now
        Log.debug("[API] #{method.upcase} #{uri}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        response = http.request(request)

        duration_ms = ((Time.now - start_time) * 1000).round(2)
        Log.debug("[API] #{method.upcase} #{uri} -> #{response.code} (#{duration_ms}ms, #{response.body.bytesize} bytes)")

        # Handle response
        unless response.is_a?(Net::HTTPSuccess)
          Log.debug("[API] Error response body: #{response.body}")
          raise Error, "HTTP #{response.code} for #{method.upcase} #{uri}: #{response.body}"
        end

        parse_json ? JSON.parse(response.body) : response
      end

      # HTTP GET with query params - returns parsed JSON
      def http_get(path, params = {})
        http_request(:get, path, params: params)
      end

      # HTTP POST with JSON body - returns parsed JSON
      def http_post_json(path, payload)
        http_request(:post, path, payload: payload)
      end

      # HTTP DELETE - returns parsed JSON
      def http_delete(path)
        http_request(:delete, path)
      end
    end
  end
end
