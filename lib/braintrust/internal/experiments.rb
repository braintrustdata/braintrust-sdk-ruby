# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  module Internal
    # Experiments module provides internal API methods for registering projects and experiments
    # Methods are marked private to prevent direct user access - use through Eval.run
    module Experiments
      # Public convenience method to register/get both project and experiment
      # @param experiment_name [String] The experiment name
      # @param project_name [String] The project name
      # @param state [State] Braintrust state with API key and URL
      # @param tags [Array<String>, nil] Optional experiment tags
      # @param metadata [Hash, nil] Optional experiment metadata
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @return [Hash] Hash with :experiment_id, :experiment_name, :project_id, :project_name
      def self.get_or_create(experiment_name, project_name, state:,
        tags: nil, metadata: nil, update: false)
        # Register/get project first
        project = register_project(project_name, state)

        # Then register/get experiment
        experiment = register_experiment(
          experiment_name,
          project["id"],
          state,
          tags: tags,
          metadata: metadata,
          update: update
        )

        {
          experiment_id: experiment["id"],
          experiment_name: experiment["name"],
          project_id: project["id"],
          project_name: project["name"]
        }
      end

      # Register or get a project by name
      # POST /v1/project with {name: "project-name"}
      # Returns existing project if already exists
      # @param name [String] Project name
      # @param state [State] Braintrust state
      # @return [Hash] Project data with "id", "name", "org_id", etc.
      # @raise [Braintrust::Error] if API call fails
      def self.register_project(name, state)
        Log.debug("Registering project: #{name}")

        uri = URI("#{state.api_url}/v1/project")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{state.api_key}"
        request.body = JSON.dump({name: name})

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true if uri.scheme == "https"

        response = http.start do |http_session|
          http_session.request(request)
        end

        Log.debug("Register project response: [#{response.code}]")

        # Handle response codes
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Failed to register project '#{name}': [#{response.code}] #{response.body}"
        end

        project = JSON.parse(response.body)
        Log.debug("Project registered: #{project["id"]} (#{project["name"]})")
        project
      end
      private_class_method :register_project

      # Register or get an experiment by name
      # POST /v1/experiment with {project_id:, name:, ensure_new:, tags:[], metadata:{}}
      # @param name [String] Experiment name
      # @param project_id [String] Project ID
      # @param state [State] Braintrust state
      # @param tags [Array<String>, nil] Optional tags
      # @param metadata [Hash, nil] Optional metadata
      # @param update [Boolean] If true, allow reusing existing experiment (ensure_new: false)
      # @return [Hash] Experiment data with "id", "name", "project_id", etc.
      # @raise [Braintrust::Error] if API call fails
      def self.register_experiment(name, project_id, state, tags: nil, metadata: nil, update: false)
        Log.debug("Registering experiment: #{name} (project: #{project_id}, update: #{update})")

        uri = URI("#{state.api_url}/v1/experiment")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{state.api_key}"

        payload = {
          project_id: project_id,
          name: name,
          ensure_new: !update  # When update=true, allow reusing existing experiment
        }
        payload[:tags] = tags if tags
        payload[:metadata] = metadata if metadata

        request.body = JSON.dump(payload)

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true if uri.scheme == "https"

        response = http.start do |http_session|
          http_session.request(request)
        end

        Log.debug("Register experiment response: [#{response.code}]")

        # Handle response codes
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Failed to register experiment '#{name}': [#{response.code}] #{response.body}"
        end

        experiment = JSON.parse(response.body)
        Log.debug("Experiment registered: #{experiment["id"]} (#{experiment["name"]})")
        experiment
      end
      private_class_method :register_experiment
    end
  end
end
