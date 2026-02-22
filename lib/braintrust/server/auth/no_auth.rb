# frozen_string_literal: true

module Braintrust
  module Server
    module Auth
      # No-op auth strategy for testing and local development.
      class NoAuth
        def authenticate(_env)
          true
        end
      end
    end
  end
end
