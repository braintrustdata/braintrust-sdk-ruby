module Test
  module Support
    module ProviderHelper
      # Get Anthropic API key for tests
      # Uses real key for recording, fake key for playback
      # @return [String] API key
      def get_anthropic_key
        key = ENV["ANTHROPIC_API_KEY"]
        (key && !key.empty?) ? key : "sk-ant-test-key-for-vcr"
      end

      # Get OpenAI API key for tests
      # Uses real key for recording, fake key for playback
      # @return [String] API key
      def get_openai_key
        key = ENV["OPENAI_API_KEY"]
        (key && !key.empty?) ? key : "sk-test-key-for-vcr"
      end
    end
  end
end
