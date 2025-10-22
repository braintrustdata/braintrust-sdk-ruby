# frozen_string_literal: true

require "logger"

module Braintrust
  # Simple logger for Braintrust SDK
  module Log
    # Default to WARN unless BRAINTRUST_DEBUG is set
    level = ENV["BRAINTRUST_DEBUG"] ? Logger::DEBUG : Logger::WARN
    @logger = Logger.new($stderr, level: level)

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

      def error(message)
        @logger.error(message)
      end
    end
  end
end
