# frozen_string_literal: true

require "openssl"

module Braintrust
  # SSL configuration helpers for macOS CRL issues
  #
  # This module configures OpenSSL to bypass Certificate Revocation List (CRL) errors
  # which commonly occur on macOS due to system certificate configuration issues.
  # All other SSL verification checks remain active for security.
  module SSLConfig
    # Configure global SSL defaults to ignore CRL errors
    # This affects all Ruby SSL connections system-wide
    def self.configure_defaults!
      # Set up a verify callback that ignores CRL errors but keeps other checks
      OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = OpenSSL::SSL::VERIFY_PEER
      OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_callback] = proc do |preverify_ok, store_context|
        if store_context.error == OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
          # Ignore CRL errors (common on macOS)
          true
        else
          # Keep all other SSL verification
          preverify_ok
        end
      end
    end
  end
end

# Auto-configure SSL defaults when this module is loaded
Braintrust::SSLConfig.configure_defaults!
