# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/template"

class Braintrust::Internal::TemplateTest < Minitest::Test
  # render - mustache format

  def test_render_substitutes_variables
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}, welcome to {{place}}!",
      {"name" => "Alice", "place" => "Wonderland"},
      format: "mustache"
    )
    assert_equal "Hello Alice, welcome to Wonderland!", result
  end

  def test_render_with_symbol_keys
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}!",
      {name: "Bob"},
      format: "mustache"
    )
    assert_equal "Hello Bob!", result
  end

  def test_render_with_nested_variables
    result = Braintrust::Internal::Template.render(
      "User: {{user.name}}, Email: {{user.email}}",
      {"user" => {"name" => "Alice", "email" => "alice@example.com"}},
      format: "mustache"
    )
    assert_equal "User: Alice, Email: alice@example.com", result
  end

  def test_render_does_not_escape_html_characters
    # LLM prompts should NOT have HTML escaping applied
    result = Braintrust::Internal::Template.render(
      "Code: {{code}}",
      {"code" => '<script>alert("test")</script> & other < > stuff'},
      format: "mustache"
    )
    assert_includes result, "<script>"
    assert_includes result, '"test"'
    assert_includes result, " & "
  end

  def test_render_preserves_ampersands_and_quotes
    result = Braintrust::Internal::Template.render(
      "Search: {{query}}",
      {"query" => 'foo & bar "baz"'},
      format: "mustache"
    )
    assert_equal 'Search: foo & bar "baz"', result
  end

  def test_render_missing_variables_become_empty
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}, your task is {{task}}.",
      {"name" => "Alice"},
      format: "mustache"
    )
    assert_equal "Hello Alice, your task is .", result
  end

  def test_render_returns_non_string_unchanged
    result = Braintrust::Internal::Template.render(nil, {}, format: "mustache")
    assert_nil result

    result = Braintrust::Internal::Template.render(123, {}, format: "mustache")
    assert_equal 123, result
  end

  # render - strict mode

  def test_render_strict_raises_on_missing_variable
    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Template.render(
        "Hello {{name}}, task: {{task}}",
        {"name" => "Alice"},
        format: "mustache",
        strict: true
      )
    end
    assert_match(/missing.*task/i, error.message)
  end

  def test_render_strict_succeeds_when_all_variables_provided
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}!",
      {"name" => "Alice"},
      format: "mustache",
      strict: true
    )
    assert_equal "Hello Alice!", result
  end

  # render - none format

  def test_render_none_returns_unchanged
    result = Braintrust::Internal::Template.render(
      "Literal {{braces}} stay as-is",
      {"braces" => "REPLACED"},
      format: "none"
    )
    assert_equal "Literal {{braces}} stay as-is", result
  end

  # render - nunjucks format

  def test_render_nunjucks_raises_error
    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Template.render(
        "{% if name %}Hello{% endif %}",
        {"name" => "Alice"},
        format: "nunjucks"
      )
    end
    assert_match(/nunjucks/i, error.message)
    assert_match(/not supported/i, error.message)
  end

  # render - unknown format

  def test_render_unknown_format_raises_error
    error = assert_raises(Braintrust::Error) do
      Braintrust::Internal::Template.render(
        "Hello {{name}}",
        {"name" => "Alice"},
        format: "jinja2"
      )
    end
    assert_match(/unknown template format/i, error.message)
    assert_match(/jinja2/i, error.message)
  end

  # render - default format (empty/nil)

  def test_render_empty_format_uses_mustache
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}!",
      {"name" => "Alice"},
      format: ""
    )
    assert_equal "Hello Alice!", result
  end

  def test_render_nil_format_uses_mustache
    result = Braintrust::Internal::Template.render(
      "Hello {{name}}!",
      {"name" => "Alice"},
      format: nil
    )
    assert_equal "Hello Alice!", result
  end

  # find_missing_variables

  def test_find_missing_variables_returns_missing
    missing = Braintrust::Internal::Template.find_missing_variables(
      "Hello {{name}}, task: {{task}}, priority: {{priority}}",
      {"name" => "Alice"}
    )
    assert_includes missing, "task"
    assert_includes missing, "priority"
    refute_includes missing, "name"
  end

  def test_find_missing_variables_returns_empty_when_all_provided
    missing = Braintrust::Internal::Template.find_missing_variables(
      "Hello {{name}}!",
      {"name" => "Alice"}
    )
    assert_empty missing
  end

  def test_find_missing_variables_handles_nested_paths
    missing = Braintrust::Internal::Template.find_missing_variables(
      "User: {{user.name}}, Email: {{user.email}}",
      {"user" => {"name" => "Alice"}}
    )
    assert_includes missing, "user.email"
    refute_includes missing, "user.name"
  end

  # resolve_variable

  def test_resolve_variable_finds_simple_key
    result = Braintrust::Internal::Template.resolve_variable(
      "name",
      {"name" => "Alice"}
    )
    assert_equal "Alice", result
  end

  def test_resolve_variable_finds_nested_key
    result = Braintrust::Internal::Template.resolve_variable(
      "user.profile.name",
      {"user" => {"profile" => {"name" => "Alice"}}}
    )
    assert_equal "Alice", result
  end

  def test_resolve_variable_returns_nil_for_missing
    result = Braintrust::Internal::Template.resolve_variable(
      "missing",
      {"name" => "Alice"}
    )
    assert_nil result
  end

  def test_resolve_variable_returns_nil_for_partial_path
    result = Braintrust::Internal::Template.resolve_variable(
      "user.profile.name",
      {"user" => {"name" => "Alice"}}
    )
    assert_nil result
  end

  def test_resolve_variable_handles_symbol_keys
    result = Braintrust::Internal::Template.resolve_variable(
      "name",
      {name: "Alice"}
    )
    assert_equal "Alice", result
  end

  # stringify_keys

  def test_stringify_keys_converts_symbols
    result = Braintrust::Internal::Template.stringify_keys({name: "Alice", age: 30})
    assert_equal({"name" => "Alice", "age" => 30}, result)
  end

  def test_stringify_keys_handles_nested_hashes
    result = Braintrust::Internal::Template.stringify_keys({
      user: {name: "Alice", profile: {city: "NYC"}}
    })
    expected = {"user" => {"name" => "Alice", "profile" => {"city" => "NYC"}}}
    assert_equal expected, result
  end

  def test_stringify_keys_returns_empty_hash_for_nil
    result = Braintrust::Internal::Template.stringify_keys(nil)
    assert_equal({}, result)
  end

  def test_stringify_keys_returns_empty_hash_for_non_hash
    result = Braintrust::Internal::Template.stringify_keys("not a hash")
    assert_equal({}, result)
  end

  def test_stringify_keys_preserves_non_hash_values
    result = Braintrust::Internal::Template.stringify_keys({
      name: "Alice",
      scores: [1, 2, 3],
      active: true
    })
    assert_equal({"name" => "Alice", "scores" => [1, 2, 3], "active" => true}, result)
  end
end
