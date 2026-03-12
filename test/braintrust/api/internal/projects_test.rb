# frozen_string_literal: true

require "test_helper"
require "braintrust/api/internal/projects"

class Braintrust::API::Internal::ProjectsTest < Minitest::Test
  def test_create_and_delete_project
    VCR.use_cassette("projects/create_and_delete") do
      state = get_integration_test_state
      projects = Braintrust::API::Internal::Projects.new(state)

      project = projects.create(name: "ruby-sdk-test-delete-me")

      assert project["id"], "project should have an id"
      assert_equal "ruby-sdk-test-delete-me", project["name"]

      deleted = projects.delete(id: project["id"])
      assert_equal project["id"], deleted["id"]
    end
  end
end
