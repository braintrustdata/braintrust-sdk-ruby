# frozen_string_literal: true

# Vendored Mustache template engine
# From mustache gem v1.1.1 - https://github.com/mustache/mustache
# License: MIT
#
# Modifications from original:
#   - Namespaced under Braintrust::Vendor to avoid conflicts
#   - Disabled HTML escaping (LLM prompts don't need HTML entity encoding)
#
# This vendored version ensures:
#   - No external dependency required
#   - Consistent behavior across all SDK users
#   - No HTML escaping that would corrupt prompts containing < > & characters

require_relative "mustache/mustache"
