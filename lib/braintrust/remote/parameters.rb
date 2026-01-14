# frozen_string_literal: true

module Braintrust
  module Remote
    # Validation error for parameter validation
    class ValidationError < Braintrust::Error; end

    # Parameter definitions for remote evaluators
    module Parameters
      # Base class for parameter definitions
      class Definition
        attr_reader :name, :default, :description

        def initialize(name, default: nil, description: nil)
          @name = name
          @default = default
          @description = description
        end

        def to_json_schema
          raise NotImplementedError
        end

        def validate(value)
          value.nil? ? @default : value
        end
      end

      # Prompt parameter - for LLM prompt configurations
      class PromptDefinition < Definition
        def initialize(name, default: nil, description: nil)
          super
          # Default prompt structure if none provided
          @default ||= {
            messages: [{role: "user", content: "{{input}}"}],
            model: "gpt-4o"
          }
        end

        def to_json_schema
          result = {type: "prompt"}
          result[:default] = @default if @default
          result[:description] = @description if @description
          result
        end

        def validate(value)
          prompt_data = value || @default
          raise ValidationError, "Parameter '#{@name}' is required" unless prompt_data

          Prompt.from_data(@name.to_s, prompt_data)
        end
      end

      # String parameter
      class StringDefinition < Definition
        def to_json_schema
          result = {
            type: "data",
            schema: {type: "string"}
          }
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil? || result.is_a?(String)

          raise ValidationError, "Parameter '#{@name}' must be a string"
        end
      end

      # Number parameter (float)
      class NumberDefinition < Definition
        attr_reader :min, :max

        def initialize(name, default: nil, description: nil, min: nil, max: nil)
          super(name, default: default, description: description)
          @min = min
          @max = max
        end

        def to_json_schema
          schema = {type: "number"}
          schema[:minimum] = @min if @min
          schema[:maximum] = @max if @max

          result = {type: "data", schema: schema}
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil?

          unless result.is_a?(Numeric)
            raise ValidationError, "Parameter '#{@name}' must be a number"
          end

          if @min && result < @min
            raise ValidationError, "Parameter '#{@name}' must be >= #{@min}"
          end

          if @max && result > @max
            raise ValidationError, "Parameter '#{@name}' must be <= #{@max}"
          end

          result.to_f
        end
      end

      # Integer parameter
      class IntegerDefinition < Definition
        attr_reader :min, :max

        def initialize(name, default: nil, description: nil, min: nil, max: nil)
          super(name, default: default, description: description)
          @min = min
          @max = max
        end

        def to_json_schema
          schema = {type: "integer"}
          schema[:minimum] = @min if @min
          schema[:maximum] = @max if @max

          result = {type: "data", schema: schema}
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil?

          is_integer = result.is_a?(Integer) || (result.is_a?(Float) && result == result.to_i)
          raise ValidationError, "Parameter '#{@name}' must be an integer" unless is_integer

          result = result.to_i

          if @min && result < @min
            raise ValidationError, "Parameter '#{@name}' must be >= #{@min}"
          end

          if @max && result > @max
            raise ValidationError, "Parameter '#{@name}' must be <= #{@max}"
          end

          result
        end
      end

      # Boolean parameter
      class BooleanDefinition < Definition
        def to_json_schema
          result = {
            type: "data",
            schema: {type: "boolean"}
          }
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil? || result == true || result == false

          raise ValidationError, "Parameter '#{@name}' must be a boolean"
        end
      end

      # Array parameter
      class ArrayDefinition < Definition
        attr_reader :items_type

        def initialize(name, default: nil, description: nil, items: "string")
          super(name, default: default, description: description)
          @items_type = items
        end

        def to_json_schema
          result = {
            type: "data",
            schema: {
              type: "array",
              items: {type: @items_type}
            }
          }
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil?

          raise ValidationError, "Parameter '#{@name}' must be an array" unless result.is_a?(Array)

          result
        end
      end

      # Enum parameter (string with allowed values)
      class EnumDefinition < Definition
        attr_reader :values

        def initialize(name, values:, default: nil, description: nil)
          super(name, default: default, description: description)
          @values = values
        end

        def to_json_schema
          result = {
            type: "data",
            schema: {
              type: "string",
              enum: @values
            }
          }
          result[:default] = @default unless @default.nil?
          result[:description] = @description if @description
          result
        end

        def validate(value)
          result = value.nil? ? @default : value
          return result if result.nil?

          unless @values.include?(result)
            raise ValidationError, "Parameter '#{@name}' must be one of: #{@values.join(", ")}"
          end

          result
        end
      end

      # Builder DSL for defining parameters
      class Builder
        attr_reader :definitions

        def initialize
          @definitions = {}
        end

        # Define a prompt parameter
        def prompt(name, default: nil, description: nil)
          @definitions[name.to_sym] = PromptDefinition.new(name, default: default, description: description)
        end

        # Define a string parameter
        def string(name, default: nil, description: nil)
          @definitions[name.to_sym] = StringDefinition.new(name, default: default, description: description)
        end

        # Define a number parameter
        def number(name, default: nil, description: nil, min: nil, max: nil)
          @definitions[name.to_sym] = NumberDefinition.new(name, default: default, description: description, min: min, max: max)
        end

        # Define an integer parameter
        def integer(name, default: nil, description: nil, min: nil, max: nil)
          @definitions[name.to_sym] = IntegerDefinition.new(name, default: default, description: description, min: min, max: max)
        end

        # Define a boolean parameter
        def boolean(name, default: nil, description: nil)
          @definitions[name.to_sym] = BooleanDefinition.new(name, default: default, description: description)
        end

        # Define an array parameter
        def array(name, default: nil, description: nil, items: "string")
          @definitions[name.to_sym] = ArrayDefinition.new(name, default: default, description: description, items: items)
        end

        # Define an enum parameter
        def enum(name, values:, default: nil, description: nil)
          @definitions[name.to_sym] = EnumDefinition.new(name, values: values, default: default, description: description)
        end

        # Convert all parameters to JSON schema
        def to_json_schema
          @definitions.transform_values(&:to_json_schema)
        end

        # Validate parameters against definitions
        def validate(params)
          validated = {}
          @definitions.each do |name, definition|
            validated[name] = definition.validate(params[name] || params[name.to_s])
          end
          validated
        end
      end

      # Validate parameters against a schema
      def self.validate(params, definitions)
        builder = Builder.new
        builder.instance_variable_set(:@definitions, definitions)
        builder.validate(params)
      end
    end
  end
end
