# frozen_string_literal: true

require "test_helper"
require_relative "../rails_server_helper"

if RAILS_SERVER_AVAILABLE
  require "rails/generators/test_case"
  require "braintrust/contrib/rails/server/generator"

  module Braintrust
    module Contrib
      module Rails
        module Server
          class GeneratorTest < ::Rails::Generators::TestCase
            tests ::Braintrust::Contrib::Rails::Server::Generators::ServerGenerator
            destination File.expand_path("../../../../tmp/server_generator", __dir__)
            setup :prepare_destination

            def test_generates_initializer_from_app_evaluators
              FileUtils.mkdir_p(File.join(destination_root, "app/evaluators"))
              File.write(
                File.join(destination_root, "app/evaluators/food_classifier.rb"),
                <<~RUBY
                  class FoodClassifier < Braintrust::Eval::Evaluator
                  end
                RUBY
              )

              run_generator

              assert_file "config/initializers/braintrust_server.rb" do |contents|
                assert_includes contents, "require \"braintrust/contrib/rails/server\""
                assert_includes contents, "Braintrust::Contrib::Rails::Server::Engine.configure"
                assert_includes contents, "\"food-classifier\" => FoodClassifier.new"
              end
            end
          end
        end
      end
    end
  end
else
  module Braintrust
    module Contrib
      module Rails
        module Server
          class GeneratorTest < Minitest::Test
            def test_skips_without_rails
              skip "Rails not available (run with: bundle exec appraisal rails-server rake test)"
            end
          end
        end
      end
    end
  end
end
