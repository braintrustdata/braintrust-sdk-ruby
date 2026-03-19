# frozen_string_literal: true

require "rails/generators"

module Braintrust
  module Contrib
    module Rails
      module Generators
        class EvalServerGenerator < ::Rails::Generators::Base
          namespace "braintrust:eval_server"
          source_root File.expand_path("templates", __dir__)

          def create_initializer
            @evaluators = discovered_evaluators
            template "braintrust_server.rb.tt", "config/initializers/braintrust_server.rb"
          end

          private

          def discovered_evaluators
            evaluator_roots.flat_map do |root|
              Dir[File.join(destination_root, root, "**/*.rb")].sort.map do |file|
                relative_path = file.delete_prefix("#{File.join(destination_root, root)}/").sub(/\.rb\z/, "")
                {
                  class_name: relative_path.split("/").map(&:camelize).join("::"),
                  slug: relative_path.tr("/", "-").tr("_", "-")
                }
              end
            end
          end

          def evaluator_roots
            %w[app/evaluators evaluators].select do |root|
              Dir.exist?(File.join(destination_root, root))
            end
          end
        end
      end
    end
  end
end
