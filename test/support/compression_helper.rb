# frozen_string_literal: true

require "zlib"
require "stringio"

module Test
  module Support
    module CompressionHelper
      def gzip_string(str)
        io = StringIO.new
        io.set_encoding("ASCII-8BIT")
        gz = Zlib::GzipWriter.new(io)
        gz.write(str)
        gz.close
        io.string
      end
    end
  end
end
