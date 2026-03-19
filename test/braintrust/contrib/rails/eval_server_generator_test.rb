# frozen_string_literal: true

require "test_helper"

if RAILS_SERVER_AVAILABLE
  require "rails/generators/test_case"
  require "generators/braintrust/contrib/rails/eval_server/eval_server_generator"

  module Braintrust
    module Contrib
      module Rails
        class EvalServerGeneratorTest < ::Rails::Generators::TestCase
          tests ::Braintrust::Contrib::Rails::Generators::EvalServerGenerator
          destination File.expand_path("../../../../tmp/eval_server_generator", __dir__)
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
              assert_includes contents, "require \"braintrust/server/rails\""
              assert_includes contents, "\"food-classifier\" => FoodClassifier.new"
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
        class EvalServerGeneratorTest < Minitest::Test
          def test_skips_without_rails
            skip "Rails not available (run with: bundle exec appraisal rails-server rake test)"
          end
        end
      end
    end
  end
end
