# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/encoding"

class Braintrust::Internal::Encoding::Base64Test < Minitest::Test
  BASE64_STDLIB_AVAILABLE = begin
    require "base64"
    true
  rescue LoadError
    false
  end

  # strict_encode64

  def test_strict_encode64_encodes_string
    result = Braintrust::Internal::Encoding::Base64.strict_encode64("Hello, World!")
    assert_equal "SGVsbG8sIFdvcmxkIQ==", result
  end

  def test_strict_encode64_encodes_binary_data
    binary = [0x89, 0x50, 0x4E, 0x47].pack("C*")
    result = Braintrust::Internal::Encoding::Base64.strict_encode64(binary)
    assert_equal "iVBORw==", result
  end

  def test_strict_encode64_encodes_empty_string
    result = Braintrust::Internal::Encoding::Base64.strict_encode64("")
    assert_equal "", result
  end

  def test_strict_encode64_produces_no_newlines
    long_string = "x" * 1000
    result = Braintrust::Internal::Encoding::Base64.strict_encode64(long_string)
    refute_includes result, "\n"
  end

  def test_strict_encode64_matches_stdlib
    skip "base64 stdlib not available" unless BASE64_STDLIB_AVAILABLE

    test_cases = [
      "Hello, World!",
      "",
      "x" * 1000,
      [0x00, 0xFF, 0x89, 0x50].pack("C*")
    ]

    test_cases.each do |input|
      expected = ::Base64.strict_encode64(input)
      actual = Braintrust::Internal::Encoding::Base64.strict_encode64(input)
      assert_equal expected, actual, "Mismatch for input: #{input.inspect}"
    end
  end

  # strict_decode64

  def test_strict_decode64_decodes_string
    result = Braintrust::Internal::Encoding::Base64.strict_decode64("SGVsbG8sIFdvcmxkIQ==")
    assert_equal "Hello, World!", result
  end

  def test_strict_decode64_decodes_binary_data
    result = Braintrust::Internal::Encoding::Base64.strict_decode64("iVBORw==")
    expected = [0x89, 0x50, 0x4E, 0x47].pack("C*")
    assert_equal expected, result
  end

  def test_strict_decode64_decodes_empty_string
    result = Braintrust::Internal::Encoding::Base64.strict_decode64("")
    assert_equal "", result
  end

  def test_strict_decode64_matches_stdlib
    skip "base64 stdlib not available" unless BASE64_STDLIB_AVAILABLE

    test_cases = [
      "SGVsbG8sIFdvcmxkIQ==",
      "",
      "eHh4eHh4eHg=",
      "AP+JUA=="
    ]

    test_cases.each do |input|
      expected = ::Base64.strict_decode64(input)
      actual = Braintrust::Internal::Encoding::Base64.strict_decode64(input)
      assert_equal expected, actual, "Mismatch for input: #{input.inspect}"
    end
  end

  # round-trip

  def test_round_trip_preserves_string_data
    original = "The quick brown fox jumps over the lazy dog"
    encoded = Braintrust::Internal::Encoding::Base64.strict_encode64(original)
    decoded = Braintrust::Internal::Encoding::Base64.strict_decode64(encoded)
    assert_equal original, decoded
  end

  def test_round_trip_preserves_binary_data
    original = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF].pack("C*")
    encoded = Braintrust::Internal::Encoding::Base64.strict_encode64(original)
    decoded = Braintrust::Internal::Encoding::Base64.strict_decode64(encoded)
    assert_equal original, decoded
  end
end
