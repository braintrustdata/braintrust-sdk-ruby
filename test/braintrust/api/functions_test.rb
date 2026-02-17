# frozen_string_literal: true

require "test_helper"

class Braintrust::API::FunctionsTest < Minitest::Test
  def setup
    @project_name = "ruby-sdk-test"
  end

  def get_test_api
    state = get_integration_test_state
    Braintrust::API.new(state: state)
  end

  def test_functions_list_with_project_name
    VCR.use_cassette("functions/list") do
      api = get_test_api
      # This test verifies that we can list functions for a given project
      # The API should return a hash with an "objects" array
      result = api.functions.list(project_name: @project_name)

      assert_instance_of Hash, result
      assert result.key?("objects")
      assert_instance_of Array, result["objects"]
    end
  end

  def test_functions_create_new_function
    VCR.use_cassette("functions/create") do
      api = get_test_api
      # This test verifies that we can create a new function (prompt) for a project
      # The function can be used as a remote task or scorer in evals
      # Note: function_data and prompt_data are separate fields
      function_slug = "test-ruby-sdk-func"

      response = api.functions.create(
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
  end

  def test_functions_invoke_by_id
    VCR.use_cassette("functions/invoke") do
      api = get_test_api
      # This test verifies that we can invoke a function by ID with input
      # The server executes the prompt and returns output
      function_slug = "test-ruby-sdk-invoke-func"

      # Create a simple echo function with proper structure
      create_response = api.functions.create(
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
      # The invoke method returns the function output directly (as returned by the HTTP API)
      result = api.functions.invoke(
        id: function_id,
        input: "world"
      )

      # Should return the output value directly (in this case, a string from the LLM)
      assert_instance_of String, result
      assert result.length > 0
    end
  end

  def test_functions_delete_by_id
    VCR.use_cassette("functions/delete") do
      api = get_test_api
      # This test verifies that we can delete a function by ID
      # This is useful for test cleanup (better than Go SDK's approach)
      function_slug = "test-ruby-sdk-delete-func"

      # Create a function
      create_response = api.functions.create(
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
      result = api.functions.delete(id: function_id)

      # Should return success (exact structure TBD based on API response)
      assert_instance_of Hash, result
    end
  end

  def test_functions_create_with_function_type
    VCR.use_cassette("functions/create_with_type") do
      api = get_test_api
      function_slug = "test-ruby-sdk-scorer-typed"

      response = api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        function_type: "scorer",
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "system", content: "You are a scorer. Return a score between 0 and 1."},
              {role: "user", content: "Score this: {{output}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "scorer", response["function_type"]

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_functions_create_with_function_schema
    VCR.use_cassette("functions/create_with_schema") do
      api = get_test_api
      function_slug = "test-ruby-sdk-tool-with-schema"

      schema = {
        parameters: {
          type: "object",
          properties: {
            query: {type: "string", description: "Search query"}
          },
          required: ["query"]
        },
        returns: {
          type: "string",
          description: "Search results"
        }
      }

      response = api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        function_type: "tool",
        function_schema: schema,
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Search for: {{query}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "tool", response["function_type"]
      assert response.key?("function_schema")

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_functions_create_scorer_helper
    VCR.use_cassette("functions/create_scorer") do
      api = get_test_api
      function_slug = "test-ruby-sdk-scorer-helper"

      response = api.functions.create_scorer(
        project_name: @project_name,
        slug: function_slug,
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "system", content: "You are a scorer. Return a score between 0 and 1."},
              {role: "user", content: "Score this output: {{output}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "scorer", response["function_type"]

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_functions_create_tool_helper
    VCR.use_cassette("functions/create_tool") do
      api = get_test_api
      function_slug = "test-ruby-sdk-tool-helper"

      response = api.functions.create_tool(
        project_name: @project_name,
        slug: function_slug,
        description: "A test tool that echoes input",
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Echo: {{input}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        },
        function_schema: {
          parameters: {
            type: "object",
            properties: {
              input: {type: "string"}
            }
          },
          returns: {type: "string"}
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "tool", response["function_type"]
      assert_equal "A test tool that echoes input", response["description"]

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_functions_create_task_helper
    VCR.use_cassette("functions/create_task") do
      api = get_test_api
      function_slug = "test-ruby-sdk-task-helper"

      response = api.functions.create_task(
        project_name: @project_name,
        slug: function_slug,
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Hello {{name}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "task", response["function_type"]

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_functions_create_llm_helper
    VCR.use_cassette("functions/create_llm") do
      api = get_test_api
      function_slug = "test-ruby-sdk-llm-helper"

      response = api.functions.create_llm(
        project_name: @project_name,
        slug: function_slug,
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Translate to French: {{text}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      assert_instance_of Hash, response
      assert response.key?("id")
      assert_equal function_slug, response["slug"]
      assert_equal "llm", response["function_type"]

      # Clean up
      api.functions.delete(id: response["id"])
    end
  end

  def test_helper_validates_prompt_data_is_hash
    VCR.use_cassette("functions/list") do
      api = get_test_api

      assert_raises(ArgumentError) do
        api.functions.create_scorer(
          project_name: @project_name,
          slug: "test-invalid",
          prompt_data: "not a hash"
        )
      end
    end
  end

  def test_helper_validates_prompt_data_has_prompt_key
    VCR.use_cassette("functions/list") do
      api = get_test_api

      assert_raises(ArgumentError) do
        api.functions.create_scorer(
          project_name: @project_name,
          slug: "test-invalid",
          prompt_data: {options: {model: "gpt-4o-mini"}}
        )
      end
    end
  end

  def test_functions_get_by_id
    VCR.use_cassette("functions/get") do
      api = get_test_api
      # This test verifies that we can get the full function data by ID,
      # including prompt_data which is needed for Prompt.load()
      function_slug = "test-ruby-sdk-get-func"

      # Create a function with prompt_data
      create_response = api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "system", content: "You are a helpful assistant."},
              {role: "user", content: "Hello {{name}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0.7}
          }
        }
      )
      function_id = create_response["id"]

      # Get the full function data
      result = api.functions.get(id: function_id)

      assert_instance_of Hash, result
      assert_equal function_id, result["id"]
      assert_equal function_slug, result["slug"]

      # Verify prompt_data is included
      assert result.key?("prompt_data")
      prompt_data = result["prompt_data"]
      assert prompt_data.key?("prompt")
      assert prompt_data["prompt"].key?("messages")
      assert_equal 2, prompt_data["prompt"]["messages"].length

      # Verify options are included
      assert prompt_data.key?("options")
      assert_equal "gpt-4o-mini", prompt_data["options"]["model"]

      # Clean up
      api.functions.delete(id: function_id)
    end
  end

  def test_functions_get_with_version
    VCR.use_cassette("functions/get_with_version") do
      api = get_test_api
      function_slug = "test-ruby-sdk-get-version"

      # Create a function and capture its version (_xact_id)
      create_response = api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Version test message"}
            ]
          },
          options: {model: "gpt-4o-mini"}
        }
      )
      function_id = create_response["id"]
      version_id = create_response["_xact_id"]

      assert version_id, "Expected _xact_id in create response"

      # Get the function with explicit version
      result = api.functions.get(id: function_id, version: version_id)

      assert_instance_of Hash, result
      assert_equal function_id, result["id"]
      assert_equal function_slug, result["slug"]
      assert result.key?("prompt_data")

      # Clean up
      api.functions.delete(id: function_id)
    end
  end
end
