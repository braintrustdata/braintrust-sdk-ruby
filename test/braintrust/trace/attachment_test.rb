# frozen_string_literal: true

require "test_helper"
require "braintrust/trace/attachment"
require "braintrust/internal/encoding"

class Braintrust::Trace::AttachmentTest < Minitest::Test
  def setup
    # Create a small test image (1x1 red PNG)
    @test_png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
      0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
      0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*")

    # Create a temporary test file
    @test_file = Tempfile.new(["test_image", ".png"])
    @test_file.binmode
    @test_file.write(@test_png_data)
    @test_file.flush
    @test_file.close
  end

  def teardown
    @test_file&.unlink
  end

  def test_from_bytes_creates_attachment
    att = Braintrust::Trace::Attachment.from_bytes("image/png", @test_png_data)

    refute_nil att
    assert_instance_of Braintrust::Trace::Attachment, att
  end

  def test_from_file_reads_and_creates_attachment
    att = Braintrust::Trace::Attachment.from_file("image/png", @test_file.path)

    refute_nil att
    assert_instance_of Braintrust::Trace::Attachment, att
  end

  def test_from_file_raises_on_missing_file
    assert_raises(Errno::ENOENT) do
      Braintrust::Trace::Attachment.from_file("image/png", "/nonexistent/file.png")
    end
  end

  def test_to_data_url_returns_correct_format
    att = Braintrust::Trace::Attachment.from_bytes("image/png", @test_png_data)
    data_url = att.to_data_url

    assert_match(/^data:image\/png;base64,/, data_url)

    # Verify it's valid base64 by extracting and decoding
    base64_part = data_url.sub(/^data:image\/png;base64,/, "")
    decoded = Braintrust::Internal::Encoding::Base64.strict_decode64(base64_part)
    assert_equal @test_png_data, decoded
  end

  def test_to_message_returns_correct_structure
    att = Braintrust::Trace::Attachment.from_bytes("image/png", @test_png_data)
    message = att.to_message

    assert_instance_of Hash, message
    assert_equal "base64_attachment", message["type"]
    assert_match(/^data:image\/png;base64,/, message["content"])
  end

  def test_to_h_aliases_to_message
    att = Braintrust::Trace::Attachment.from_bytes("image/png", @test_png_data)

    assert_equal att.to_message, att.to_h
  end

  def test_attachment_is_reusable
    att = Braintrust::Trace::Attachment.from_bytes("image/png", @test_png_data)

    # Call to_data_url multiple times
    url1 = att.to_data_url
    url2 = att.to_data_url

    # Both should work and return the same result
    assert_equal url1, url2

    # Call to_message multiple times
    msg1 = att.to_message
    msg2 = att.to_message

    assert_equal msg1, msg2
  end

  def test_from_url_fetches_remote_image
    stub = stub_request(:get, "https://example.com/image.png")
      .to_return(status: 200, body: @test_png_data, headers: {"Content-Type" => "image/png"})

    att = Braintrust::Trace::Attachment.from_url("https://example.com/image.png")

    refute_nil att
    assert_instance_of Braintrust::Trace::Attachment, att

    # Should be able to convert to data URL
    data_url = att.to_data_url
    assert_match(/^data:image\/png;base64,/, data_url)
  ensure
    remove_request_stub(stub)
  end

  def test_from_url_handles_content_type_from_response
    stub = stub_request(:get, "https://example.com/photo.jpg")
      .to_return(status: 200, body: "fake jpeg data", headers: {"Content-Type" => "image/jpeg"})

    att = Braintrust::Trace::Attachment.from_url("https://example.com/photo.jpg")

    refute_nil att
    data_url = att.to_data_url

    # Should detect JPEG content type
    assert_match(/^data:image\/jpeg;base64,/, data_url)
  ensure
    remove_request_stub(stub)
  end

  def test_from_url_raises_on_network_error
    stub = stub_request(:get, "https://example.com/nonexistent.png")
      .to_return(status: 404)

    error = assert_raises(StandardError) do
      Braintrust::Trace::Attachment.from_url("https://example.com/nonexistent.png")
    end

    assert_match(/Failed to fetch URL: 404/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_different_content_types
    test_data = "test content"

    types = [
      "image/png",
      "image/jpeg",
      "image/gif",
      "image/webp",
      "text/plain",
      "application/pdf"
    ]

    types.each do |content_type|
      att = Braintrust::Trace::Attachment.from_bytes(content_type, test_data)
      data_url = att.to_data_url

      assert_match(/^data:#{Regexp.escape(content_type)};base64,/, data_url)
    end
  end
end
