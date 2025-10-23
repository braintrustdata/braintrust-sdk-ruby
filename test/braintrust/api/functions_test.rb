# frozen_string_literal: true

require "test_helper"

class Braintrust::API::FunctionsTest < Minitest::Test
  def setup
    flunk "BRAINTRUST_API_KEY not set" unless ENV["BRAINTRUST_API_KEY"]

    @state = Braintrust.init(set_global: false, blocking_login: true)
    @api = Braintrust::API.new(state: @state)
    @project_name = "ruby-sdk-test"
  end

  def test_functions_list_with_project_name
    # This test verifies that we can list functions for a given project
    # The API should return a hash with an "objects" array
    result = @api.functions.list(project_name: @project_name)

    assert_instance_of Hash, result
    assert result.key?("objects")
    assert_instance_of Array, result["objects"]
  end

  def test_functions_create_new_function
    # This test verifies that we can create a new function (prompt) for a project
    # The function can be used as a remote task or scorer in evals
    # Note: function_data and prompt_data are separate fields
    function_slug = unique_name("test-func")

    response = @api.functions.create(
      project_name: @project_name,
      slug: function_slug,
      function_data: {type: "prompt"},
      prompt_data: {
        prompt: {
          type: "chat",
          messages: [
            {role: "user", content: "Test prompt"}
          ]
        },
        options: {
          model: "gpt-4o-mini"
        }
      }
    )

    assert_instance_of Hash, response
    assert response.key?("id")
    assert response.key?("slug")
    assert_equal function_slug, response["slug"]
  end

  def test_functions_invoke_by_id
    # This test verifies that we can invoke a function by ID with input
    # The server executes the prompt and returns output
    function_slug = unique_name("invoke-func")

    # Create a simple echo function with proper structure
    create_response = @api.functions.create(
      project_name: @project_name,
      slug: function_slug,
      function_data: {type: "prompt"},
      prompt_data: {
        prompt: {
          type: "chat",
          messages: [
            {role: "user", content: "Say hello to {{input}}"}
          ]
        },
        options: {
          model: "gpt-4o-mini",
          params: {temperature: 0}
        }
      }
    )
    function_id = create_response["id"]

    # Invoke the function
    # The invoke method returns the output value directly (not wrapped in a hash)
    result = @api.functions.invoke(
      id: function_id,
      input: "world"
    )

    # Should return a string output from the LLM
    assert_instance_of String, result
    assert result.length > 0
  end

  def test_functions_delete_by_id
    # This test verifies that we can delete a function by ID
    # This is useful for test cleanup (better than Go SDK's approach)
    function_slug = unique_name("delete-func")

    # Create a function
    create_response = @api.functions.create(
      project_name: @project_name,
      slug: function_slug,
      function_data: {type: "prompt"},
      prompt_data: {
        prompt: {
          type: "chat",
          messages: [
            {role: "user", content: "Test"}
          ]
        },
        options: {
          model: "gpt-4o-mini"
        }
      }
    )
    function_id = create_response["id"]

    # Delete it
    result = @api.functions.delete(id: function_id)

    # Should return success (exact structure TBD based on API response)
    assert_instance_of Hash, result
  end
end
