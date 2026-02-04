# frozen_string_literal: true

# Vendored from mustache gem v1.1.1
# https://github.com/mustache/mustache
# License: MIT
# Modifications: Namespaced under Braintrust::Vendor

module Braintrust
  module Vendor
    class Mustache
      # A ContextMiss is raised whenever a tag's target can not be found
      # in the current context if `Mustache#raise_on_context_miss?` is
      # set to true.
      #
      # For example, if your View class does not respond to `music` but
      # your template contains a `{{music}}` tag this exception will be raised.
      #
      # By default it is not raised. See Mustache.raise_on_context_miss.
      class ContextMiss < RuntimeError; end
    end
  end
end
