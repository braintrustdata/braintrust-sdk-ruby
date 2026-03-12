# frozen_string_literal: true

require "logger"

module Braintrust
  # Simple logger for Braintrust SDK
  module Log
    # Default to WARN unless BRAINTRUST_DEBUG is set
    level = ENV["BRAINTRUST_DEBUG"] ? Logger::DEBUG : Logger::WARN
    @logger = Logger.new($stderr, level: level)
    @warned = Set.new

    class << self
      attr_accessor :logger

      def debug(message)
        @logger.debug(message)
      end

      def info(message)
        @logger.info(message)
      end

      def warn(message)
        @logger.warn(message)
      end

      # Emit a warning only once per unique key.
      # Subsequent calls with the same key are silently ignored.
      def warn_once(key, message)
        return if @warned.include?(key)
        @warned.add(key)
        @logger.warn(message)
      end

      def error(message)
        @logger.error(message)
      end
    end
  end
end
