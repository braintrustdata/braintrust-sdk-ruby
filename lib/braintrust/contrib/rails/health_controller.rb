# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      class HealthController < ApplicationController
        def show
          render json: {"status" => "ok"}
        end
      end
    end
  end
end
