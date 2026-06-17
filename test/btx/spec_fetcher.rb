# frozen_string_literal: true

require "fileutils"
require "open-uri"
require "rubygems/package"
require "zlib"
require "tmpdir"

module Braintrust
  module BTX
    # Downloads and caches the braintrust-spec tarball at a pinned ref.
    #
    # The spec lives in braintrustdata/braintrust-spec and is fetched as a
    # GitHub source tarball. The top-level directory (e.g. "braintrust-spec-af0e006/")
    # is stripped during extraction so the cache contains "test/llm_span/" directly.
    #
    # Fetching is idempotent: if the cache already contains the spec, no network
    # call is made. This makes repeated local runs instant.
    module SpecFetcher
      BTX_DIR = File.expand_path(__dir__)
      SPEC_REF_FILE = File.join(BTX_DIR, "spec-ref.txt")
      SPEC_CACHE_DIR = File.join(BTX_DIR, ".spec-cache")

      module_function

      # @return [String] the pinned spec ref (e.g. "v0.0.1")
      def spec_ref
        File.read(SPEC_REF_FILE).strip
      end

      # Resolve the llm_span spec root, fetching the tarball if needed.
      #
      # Honors the BTX_SPEC_ROOT environment variable as an override (used by CI
      # environments that pre-download the spec separately).
      #
      # @return [String] absolute path to the test/llm_span directory
      def spec_root
        env = ENV["BTX_SPEC_ROOT"]
        return env if env && !env.empty?

        fetch_if_needed(spec_ref)
      end

      # Download braintrust-spec@ref into the local cache; skip if already present.
      #
      # @param ref [String] the spec ref to fetch
      # @return [String] absolute path to the test/llm_span directory
      def fetch_if_needed(ref)
        cache_dir = File.join(SPEC_CACHE_DIR, ref)
        llm_span_root = File.join(cache_dir, "test", "llm_span")

        return llm_span_root if File.directory?(llm_span_root)

        FileUtils.mkdir_p(SPEC_CACHE_DIR)
        warn "[btx] Fetching braintrust-spec@#{ref} ..."

        url = "https://github.com/braintrustdata/braintrust-spec/archive/#{ref}.tar.gz"

        # Extract into a unique temp dir next to the final cache_dir so the
        # eventual rename is atomic (same filesystem).
        tmp_dir = Dir.mktmpdir("#{ref}.tmp.", SPEC_CACHE_DIR)
        begin
          extract_tarball(url, tmp_dir)

          begin
            File.rename(tmp_dir, cache_dir)
          rescue SystemCallError
            # Another process beat us to it; that's fine as long as the spec exists.
            raise unless File.directory?(llm_span_root)
          end
        ensure
          FileUtils.rm_rf(tmp_dir) if File.directory?(tmp_dir)
        end

        unless File.directory?(llm_span_root)
          raise "Expected llm_span dir not found after fetch: #{llm_span_root}"
        end

        warn "[btx] Spec cached at #{llm_span_root}"
        llm_span_root
      end

      # Download the tarball at +url+ and extract it into +dest_dir+, stripping
      # the top-level directory component.
      def extract_tarball(url, dest_dir)
        URI.open(url, "rb") do |remote| # rubocop:disable Security/Open
          Zlib::GzipReader.wrap(remote) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              tar.each do |entry|
                rel = strip_top_level(entry.full_name)
                next if rel.nil? || rel.empty?

                dest = File.join(dest_dir, rel)

                if entry.directory?
                  FileUtils.mkdir_p(dest)
                elsif entry.file?
                  FileUtils.mkdir_p(File.dirname(dest))
                  File.binwrite(dest, entry.read)
                end
              end
            end
          end
        end
      end

      # Strip the leading path component (the GitHub archive top-level dir).
      def strip_top_level(name)
        parts = name.split("/")
        return nil if parts.length <= 1
        parts[1..].join("/")
      end
    end
  end
end
