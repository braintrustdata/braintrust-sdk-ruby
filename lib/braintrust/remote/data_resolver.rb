# frozen_string_literal: true

module Braintrust
  module Remote
    # Resolves data specifications into EvalCase arrays
    #
    # The Braintrust playground sends data in several formats:
    # - Inline array: [{ input: "...", expected: "..." }, ...]
    # - Nested inline: { data: [{ input: "...", expected: "..." }, ...] }
    # - Dataset reference: { dataset_id: "uuid" }
    # - Dataset by name: { project_name: "...", dataset_name: "..." }
    #
    # This class handles all formats and converts them to EvalCase objects.
    #
    # @example Resolve inline data
    #   resolver = DataResolver.new(api)
    #   cases = resolver.resolve([{ "input" => "hello" }])
    #   # => [#<EvalCase input="hello">]
    #
    # @example Resolve dataset by ID
    #   resolver = DataResolver.new(api)
    #   cases = resolver.resolve({ "dataset_id" => "abc-123" })
    #   # => [#<EvalCase ...>, ...]
    #
    class DataResolver
      # @param api [Braintrust::API] Braintrust API client
      def initialize(api)
        @api = api
      end

      # Resolve a data specification into EvalCase objects
      #
      # @param data_spec [Array, Hash, nil] The data specification from the request
      # @return [Array<EvalCase>, nil] Array of EvalCase objects, or nil if no data
      # @raise [ArgumentError] If the data format is invalid or unsupported
      #
      def resolve(data_spec)
        return nil unless data_spec

        if data_spec.is_a?(Array)
          # Inline data array
          Braintrust::Log.debug("[DataResolver] Using inline data array with #{data_spec.length} items")
          data_spec.map { |item| EvalCase.from_hash(item) }

        elsif data_spec.is_a?(Hash) && data_spec["data"].is_a?(Array)
          # Nested inline data (RunEvalData2 format)
          Braintrust::Log.debug("[DataResolver] Using nested inline data with #{data_spec["data"].length} items")
          data_spec["data"].map { |item| EvalCase.from_hash(item) }

        elsif data_spec.is_a?(Hash) && data_spec["dataset_id"]
          # Fetch by dataset ID (RunEvalData format)
          Braintrust::Log.debug("[DataResolver] Fetching dataset by ID: #{data_spec["dataset_id"]}")
          fetch_by_dataset_id(data_spec["dataset_id"])

        elsif data_spec.is_a?(Hash) && data_spec["project_name"] && data_spec["dataset_name"]
          # Fetch by project/dataset name (RunEvalData1 format)
          Braintrust::Log.debug("[DataResolver] Fetching dataset by name: #{data_spec["project_name"]}/#{data_spec["dataset_name"]}")
          fetch_by_name(data_spec["project_name"], data_spec["dataset_name"])

        else
          keys = data_spec.is_a?(Hash) ? data_spec.keys.join(", ") : data_spec.class.to_s
          raise ArgumentError, "Invalid data format: #{keys}"
        end
      end

      # Extract dataset_id from data_spec if present
      #
      # @param data_spec [Hash, Array, nil] The data specification
      # @return [String, nil] The dataset ID, or nil if inline data
      #
      def self.extract_dataset_id(data_spec)
        return nil unless data_spec.is_a?(Hash)
        data_spec["dataset_id"]
      end

      private

      def fetch_by_dataset_id(dataset_id)
        rows = @api.datasets.fetch_rows(id: dataset_id)
        rows.map { |row| EvalCase.from_hash(row) }
      end

      def fetch_by_name(project_name, dataset_name)
        # Look up the dataset first
        dataset = @api.datasets.get(project_name: project_name, name: dataset_name)
        fetch_by_dataset_id(dataset["id"])
      end
    end
  end
end
