# frozen_string_literal: true

require_relative "api"
require_relative "internal/origin"

module Braintrust
  # High-level interface for working with Braintrust datasets.
  # Provides both eager loading and lazy enumeration for efficient access to dataset records.
  #
  # @example Basic usage (uses global state)
  #   Braintrust.init(api_key: "...")
  #   dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project")
  #   dataset.each { |record| puts record[:input] }
  #
  # @example With explicit state
  #   state = Braintrust.init(api_key: "...")
  #   dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project", state: state)
  #
  # @example Eager loading for small datasets
  #   records = dataset.fetch_all(limit: 100)
  #
  # @example Using Enumerable methods
  #   dataset.take(10)
  #   dataset.select { |r| r[:tags]&.include?("important") }
  #
  # @example With version pinning
  #   dataset = Braintrust::Dataset.new(name: "my-dataset", project: "my-project", version: "1.0")
  class Dataset
    include Enumerable

    # Default number of records to fetch per API page
    DEFAULT_PAGE_SIZE = 1000

    attr_reader :name, :project, :version

    # Initialize a dataset reference
    # @param name [String, nil] Dataset name (required if id not provided)
    # @param id [String, nil] Dataset UUID (required if name not provided)
    # @param project [String, nil] Project name (required if using name)
    # @param version [String, nil] Optional version to pin to
    # @param state [State, nil] Braintrust state (defaults to global state)
    def initialize(name: nil, id: nil, project: nil, version: nil, state: nil)
      @name = name
      @provided_id = id
      @project = project
      @version = version
      @api = API.new(state: state)
      @resolved_id = nil
      @metadata = nil

      validate_params!
    end

    # Get the dataset ID, resolving from name if necessary
    # @return [String] Dataset UUID
    def id
      return @provided_id if @provided_id
      resolve_name! unless @resolved_id
      @resolved_id
    end

    # Get the dataset metadata from the API
    # Makes an API call if metadata hasn't been fetched yet.
    # Note: When initialized with name, metadata is fetched during name resolution.
    # When initialized with ID, this triggers a separate get_by_id call.
    # @return [Hash] Dataset metadata including name, description, created, etc.
    def metadata
      fetch_metadata! unless @metadata
      @metadata
    end

    # Fetch all records eagerly into an array
    # @param limit [Integer, nil] Maximum records to return (nil for all)
    # @return [Array<Hash>] Array of records with :input, :expected, :tags, :metadata, :origin
    def fetch_all(limit: nil)
      records = []
      each_record(limit: limit) { |record| records << record }
      records
    end

    # Iterate over records lazily (implements Enumerable)
    # Fetches pages on demand for memory efficiency with large datasets.
    # @yield [Hash] Each record with :input, :expected, :tags, :metadata, :origin
    def each(&block)
      return enum_for(:each) unless block_given?
      each_record(&block)
    end

    private

    def validate_params!
      if @provided_id.nil? && @name.nil?
        raise ArgumentError, "must specify either :name or :id"
      end

      if @name && @project.nil?
        raise ArgumentError, ":project is required when using :name"
      end
    end

    # Resolve dataset name to ID (also fetches metadata as side effect)
    def resolve_name!
      @metadata = @api.datasets.get(project_name: @project, name: @name)
      @resolved_id = @metadata["id"]
    end

    # Fetch metadata explicitly (for when ID was provided directly)
    def fetch_metadata!
      if @provided_id
        @metadata = @api.datasets.get_by_id(id: @provided_id)
      else
        resolve_name! unless @metadata
      end
    end

    # Core iteration with pagination
    # @param limit [Integer, nil] Maximum records to return
    def each_record(limit: nil, &block)
      dataset_id = id  # Resolve once
      cursor = nil
      count = 0

      loop do
        page_limit = if limit
          [DEFAULT_PAGE_SIZE, limit - count].min
        else
          DEFAULT_PAGE_SIZE
        end

        result = @api.datasets.fetch(
          id: dataset_id,
          limit: page_limit,
          cursor: cursor,
          version: @version
        )

        result[:records].each do |raw_record|
          record = build_record(raw_record, dataset_id)
          block.call(record)
          count += 1
          break if limit && count >= limit
        end

        # Stop if we've hit the limit or no more pages
        break if limit && count >= limit

        cursor = result[:cursor]
        break unless cursor
      end
    end

    # Build a normalized record hash from raw API response
    # @param raw [Hash] Raw record from API
    # @param dataset_id [String] Dataset ID for origin
    # @return [Hash] Normalized record with origin
    def build_record(raw, dataset_id)
      record = {}
      record[:input] = raw["input"] if raw.key?("input")
      record[:expected] = raw["expected"] if raw.key?("expected")
      record[:tags] = raw["tags"] if raw.key?("tags")
      record[:metadata] = raw["metadata"] if raw.key?("metadata")

      origin = build_origin(raw, dataset_id)
      record[:origin] = origin if origin

      record
    end

    # Build origin JSON for tracing/linking
    # @param raw [Hash] Raw record from API
    # @param dataset_id [String] Dataset ID (fallback if not in record)
    # @return [String, nil] JSON-serialized origin, or nil if record lacks required fields
    def build_origin(raw, dataset_id)
      return nil unless raw["id"] && raw["_xact_id"]

      Internal::Origin.to_json(
        object_type: "dataset",
        object_id: raw["dataset_id"] || dataset_id,
        id: raw["id"],
        xact_id: raw["_xact_id"],
        created: raw["created"]
      )
    end
  end

  # Value object wrapping a dataset UUID for resolution by ID.
  # Used by Eval.run to distinguish dataset-by-ID from dataset-by-name.
  DatasetId = Struct.new(:id, keyword_init: true)
end
