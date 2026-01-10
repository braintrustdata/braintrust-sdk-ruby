module Test
  module Support
    module FixtureHelper
      # Minimal valid PNG image (10x10)
      PNG_DATA = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x0a,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x02, 0x50, 0x58, 0xea, 0x00, 0x00, 0x00,
        0x12, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xf8, 0xcf, 0xc0, 0x80,
        0x07, 0x31, 0x8c, 0x4a, 0x63, 0x43, 0x00, 0xb7, 0xca, 0x63, 0x9d, 0xd6,
        0xd5, 0xef, 0x74, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
        0x42, 0x60, 0x82
      ].pack("C*").freeze

      # Create a temporary PNG file and yield to the block
      # Uses a minimal valid 10x10 PNG image by default
      # @param data [String] PNG data (default: PNG_DATA constant)
      # @param filename [String] prefix for the temp file name
      # @param extension [String] extension for the temp file name
      # @yield [Tempfile] the temporary PNG file
      def with_png_file(data: PNG_DATA, filename: "test_image", extension: ".png", &block)
        with_tmp_file(data: data, filename: filename, extension: extension, binary: true, &block)
      end

      # Create a temporary file and yield to the block
      # File is automatically cleaned up after the block
      # @param data [String] content to write to the file (default: empty)
      # @param filename [String] prefix for the temp file name (or exact name if exact_name: true)
      # @param extension [String] extension for the temp file name
      # @param binary [Boolean] whether to write in binary mode
      # @param exact_name [Boolean] if true, use exact filename without random suffix
      # @yield [Tempfile, String] the temporary file (Tempfile) or path (String if exact_name)
      def with_tmp_file(data: "", filename: "test", extension: ".txt", binary: false, exact_name: false)
        return unless block_given?

        if exact_name
          Dir.mktmpdir do |dir|
            path = File.join(dir, "#{filename}#{extension}")
            File.write(path, data, mode: binary ? "wb" : "w")
            yield path
          end
        else
          require "tempfile"
          tmpfile = Tempfile.new([filename, extension])
          tmpfile.binmode if binary
          tmpfile.write(data)
          tmpfile.close

          begin
            yield(tmpfile)
          ensure
            tmpfile.unlink
          end
        end
      end
    end
  end
end
