# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Handlers
      # GET / — simple health check endpoint.
      class Health
        def call(_env)
          [200, {"content-type" => "application/json"}, [JSON.dump({"status" => "ok"})]]
        end
      end
    end
  end
end
