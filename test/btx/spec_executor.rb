# frozen_string_literal: true

require "opentelemetry/sdk"
require "securerandom"
require "braintrust"
require_relative "spec_loader"

module Braintrust
  module BTX
    # Result of executing a spec: the root span id plus the captured OTel spans.
    ExecutionResult = Struct.new(:root_span_id, :otel_spans, keyword_init: true)

    # Executes BTX llm_span specs in-process using the Braintrust Ruby SDK.
    #
    # All provider API calls for a spec are made under a single parent ("root")
    # span. Spans are always captured in-memory via an InMemorySpanExporter so
    # they can be converted to brainstore format. In live mode (+live: true+) a
    # real OTLP exporter is *also* attached so spans are ingested into Braintrust
    # and can be fetched back via BTQL. The returned root_span_id (hex trace id)
    # is used in live mode to locate those spans.
    class SpecExecutor
      # The [provider, endpoint] pairs the Ruby SDK can instrument. Specs whose
      # provider/endpoint is not in this set are skipped by the runner (the SDK
      # has no instrumentation to exercise, e.g. bedrock and google).
      SUPPORTED_ENDPOINTS = [
        ["openai", "/v1/chat/completions"],
        ["openai", "/v1/responses"],
        ["anthropic", "/v1/messages"]
      ].freeze

      # @return [Boolean] whether the SDK can instrument this spec
      def self.supported?(spec)
        SUPPORTED_ENDPOINTS.include?([spec.provider, spec.endpoint])
      end

      # @param state [Braintrust::State] state used for span attribution
      # @param live [Boolean] when true, also export spans to the Braintrust backend
      def initialize(state, live: false)
        @state = state
        @live = live
      end

      # Execute +spec+ and return the captured spans.
      #
      # @param spec [LlmSpanSpec]
      # @return [ExecutionResult]
      def execute(spec)
        exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

        simple_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        bt_processor = Braintrust::Trace::SpanProcessor.new(simple_processor, @state)
        tracer_provider.add_span_processor(bt_processor)

        # Live mode: also ship spans to the Braintrust backend via OTLP so they
        # can be queried back through BTQL.
        if @live
          otlp = Braintrust::Trace::SpanExporter.new(
            endpoint: "#{@state.api_url}/otel/v1/traces",
            api_key: @state.api_key
          )
          batch = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otlp)
          tracer_provider.add_span_processor(Braintrust::Trace::SpanProcessor.new(batch, @state))
        end

        Braintrust::Contrib.init(tracer_provider: tracer_provider)
        instrument!(spec.provider)

        client = build_client(spec.provider)

        tracer = tracer_provider.tracer("btx")
        root_span_id = nil
        tracer.in_span(spec.name) do |root_span|
          root_span_id = root_span.context.hex_trace_id
          dispatch(spec, client)
        end

        tracer_provider.force_flush
        spans = exporter.finished_spans

        ExecutionResult.new(root_span_id: root_span_id, otel_spans: spans)
      end

      private

      def instrument!(provider)
        case provider
        when "openai"
          require "openai"
          Braintrust::Contrib::OpenAI::Integration.patch!
        when "anthropic"
          require "anthropic"
          Braintrust::Contrib::Anthropic::Integration.patch!
        else
          raise NotImplementedError, "BTX executor: provider #{provider.inspect} not implemented"
        end
      end

      def build_client(provider)
        case provider
        when "openai"
          ::OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"] || "sk-test-key-for-vcr")
        when "anthropic"
          ::Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"] || "sk-ant-test-key-for-vcr")
        else
          raise NotImplementedError, "BTX executor: provider #{provider.inspect} not implemented"
        end
      end

      def dispatch(spec, client)
        # Spec-level features applied uniformly across every provider path:
        #   - variables / !gen placeholders interpolated into {{...}} templates
        #   - top-level headers passed through unchanged via request_options
        vars = resolve_variables(spec.variables)
        request_options = build_request_options(spec.headers)
        requests = spec.requests.map { |req| interpolate(deep_symbolize(req), vars) }

        case [spec.provider, spec.endpoint]
        when ["openai", "/v1/chat/completions"]
          execute_chat_completions(requests, client, request_options)
        when ["openai", "/v1/responses"]
          execute_responses(requests, client, request_options)
        when ["anthropic", "/v1/messages"]
          execute_anthropic_messages(requests, client, request_options)
        else
          raise NotImplementedError,
            "BTX executor: provider=#{spec.provider.inspect} endpoint=#{spec.endpoint.inspect} not implemented"
        end
      end

      # ---- OpenAI chat completions ----

      def execute_chat_completions(requests, client, request_options)
        history = []

        requests.each do |req|
          full = req.dup
          messages = full.delete(:messages) || []
          full[:messages] = history + messages
          full[:request_options] = request_options if request_options

          streaming = full.delete(:stream)

          history += messages

          if streaming
            # Keep stream_options (e.g. include_usage) so the snapshot carries usage.
            stream = client.chat.completions.stream(**full)
            final = nil
            stream.each { |_event| } # consume
            final = stream.current_completion_snapshot if stream.respond_to?(:current_completion_snapshot)
            if final&.choices&.any?
              msg = final.choices.first.message
              history << {role: "assistant", content: msg.content || ""}
            end
          else
            response = client.chat.completions.create(**full)
            if response.choices&.any?
              msg = response.choices.first.message
              history << {role: "assistant", content: msg.content || ""}
            end
          end
        end
      end

      # ---- OpenAI responses ----

      def execute_responses(requests, client, request_options)
        history = []

        requests.each do |req|
          full = req.dup
          input = full.delete(:input) || []
          full[:input] = history + input
          full[:request_options] = request_options if request_options

          response = client.responses.create(**full)

          history += input
          if response.respond_to?(:output) && response.output
            history += response.output.map { |item| item.respond_to?(:to_h) ? item.to_h : item }
          end
        end
      end

      # ---- Anthropic messages ----

      def execute_anthropic_messages(requests, client, request_options)
        history = []

        requests.each do |req|
          full = req.dup
          messages = full.delete(:messages) || []
          full[:messages] = history + messages

          # The official anthropic Ruby gem names the system param `system_`.
          if full.key?(:system)
            full[:system_] = full.delete(:system)
          end

          # Pass the spec's headers through unchanged (e.g. anthropic-beta).
          full[:request_options] = request_options if request_options

          streaming = full.delete(:stream)

          history += messages

          if streaming
            stream = client.messages.stream(**full)
            stream.each { |_event| } # consume
            if stream.respond_to?(:accumulated_message)
              msg = stream.accumulated_message
              text = text_from_anthropic(msg)
              history << {role: "assistant", content: text} if text
            end
          else
            response = client.messages.create(**full)
            text = text_from_anthropic(response)
            history << {role: "assistant", content: text} if text
          end
        end
      end

      def text_from_anthropic(message)
        return nil unless message.respond_to?(:content) && message.content
        blocks = message.content.filter_map do |block|
          block.text if block.respond_to?(:text)
        end
        blocks.empty? ? nil : blocks.join(" ")
      end

      # Recursively convert string keys to symbols (the Ruby provider SDKs
      # expect symbol-keyed kwargs). Resolves !gen placeholders to a value.
      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), acc|
            acc[k.to_sym] = deep_symbolize(v)
          end
        when Array
          value.map { |v| deep_symbolize(v) }
        when GenMatcher
          generated_value(value.name)
        else
          value
        end
      end

      def generated_value(name)
        case name
        when "vcr_nonce"
          # In live mode (no cassette) the nonce must be unique to force a
          # provider-side cache miss so prompt-cache creation metrics are
          # non-zero. In record/replay the nonce must be deterministic so the
          # request body matches the committed cassette.
          @live ? "btx-#{SecureRandom.hex(8)}" : "btx-nonce"
        else
          "btx-#{name}"
        end
      end

      # Resolve the spec's `variables` map (which may contain !gen placeholders)
      # into concrete string values keyed by variable name.
      # @param variables [Hash] raw variables map from the spec
      # @return [Hash{String=>String}]
      def resolve_variables(variables)
        (variables || {}).each_with_object({}) do |(name, value), acc|
          acc[name.to_s] = (value.is_a?(GenMatcher) ? generated_value(value.name) : value).to_s
        end
      end

      # Substitute {{var}} templates in every string within +obj+ using +vars+.
      def interpolate(obj, vars)
        return obj if vars.empty?

        case obj
        when Hash
          obj.transform_values { |v| interpolate(v, vars) }
        when Array
          obj.map { |v| interpolate(v, vars) }
        when String
          obj.gsub(/\{\{\s*([\w-]+)\s*\}\}/) { vars[$1] || $~[0] }
        else
          obj
        end
      end

      # Build the anthropic gem request_options for the spec's headers, or nil
      # when there are none. The headers MUST be passed through unchanged.
      def build_request_options(headers)
        return nil if headers.nil? || headers.empty?
        {extra_headers: headers.transform_keys(&:to_s)}
      end
    end
  end
end
