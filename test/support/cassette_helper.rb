module Test
  module Support
    module CassetteHelper
      # Cassette path for a gem whose wire format varies by version.
      #
      # Cassettes live in folders named for the minimum gem version they were
      # recorded against, with underscores for dots (VCR rewrites dots in cassette
      # paths): contrib/<gem>/<x_y_z>/<name>.yml. The loaded gem
      # resolves to the newest folder at or below its version, so releases with
      # no wire changes replay the previous folder. A release that breaks them
      # gets a new folder holding a full set of cassettes, recorded by running
      # its appraisal with VCR_MODE=all and a real API key.
      #
      # @param gem_name [String] name of the gem under test (e.g. "anthropic")
      # @param name [String] cassette name within the version folder
      # @return [String] cassette path for VCR.use_cassette
      def versioned_cassette(gem_name, name)
        "contrib/#{gem_name}/#{cassette_version_floor(gem_name)}/#{name}"
      end

      # Newest version folder at or below the given gem version.
      # @param gem_name [String] name of the gem under test
      # @param version [Gem::Version] version to resolve (default: loaded gem version)
      # @param dir [String] folder holding the version folders
      # @return [String] name of the version folder
      # @raise [ArgumentError] if the gem isn't loaded or no folder covers the version
      def cassette_version_floor(gem_name, version: Gem.loaded_specs[gem_name]&.version, dir: File.join(VCR.configuration.cassette_library_dir, "contrib", gem_name))
        raise ArgumentError, "#{gem_name} gem not loaded" unless version

        floor = Dir.children(dir)
          .select { |child| child.match?(/\A\d+(_\d+)*\z/) && File.directory?(File.join(dir, child)) }
          .select { |child| Gem::Version.new(child.tr("_", ".")) <= version }
          .max_by { |child| Gem::Version.new(child.tr("_", ".")) }

        raise ArgumentError, "no cassettes for #{gem_name} #{version} in #{dir}" unless floor

        floor
      end
    end
  end
end
