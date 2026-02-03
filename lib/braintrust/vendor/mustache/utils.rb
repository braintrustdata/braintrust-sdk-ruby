# frozen_string_literal: true

# Vendored from mustache gem v1.1.1
# https://github.com/mustache/mustache
# License: MIT
# Modifications: Namespaced under Braintrust::Vendor

module Braintrust
  module Vendor
    class Mustache
      module Utils
        class String
          def initialize(string)
            @string = string
          end

          def classify
            @string.split("/").map do |namespace|
              namespace.split(/[-_]/).map do |part|
                part[0] = part.chars.first.upcase
                part
              end.join
            end.join("::")
          end

          def underscore(view_namespace)
            @string
              .dup
              .split("#{view_namespace}::")
              .last
              .split("::")
              .map do |part|
                part[0] = part[0].downcase
                part.gsub(/[A-Z]/) { |s| "_" << s.downcase }
              end
              .join("/")
          end
        end
      end
    end
  end
end
