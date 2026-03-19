# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      module Server
        class ListController < ApplicationController
          def show
            result = Engine.list_service.call
            render json: result
          end
        end
      end
    end
  end
end
