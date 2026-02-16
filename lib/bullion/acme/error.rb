# frozen_string_literal: true

module Bullion
  module Acme
    # ACME protocol errors super class
    class Error < Bullion::Error
      # @see https://tools.ietf.org/html/rfc8555#section-6.7
      def acme_type
        "genericError"
      end

      def acme_preface
        "urn:ietf:params:acme:error:"
      end

      def acme_error
        acme_preface + acme_type
      end
    end

    module Errors
      # ACME exception for nonexistent accounts
      class AccountDoesNotExist < Bullion::Acme::Error
        def acme_type = "accountDoesNotExist"
      end

      # ACME exception for bad CSRs
      class BadCsr < Bullion::Acme::Error
        def acme_type = "badCSR"
      end

      # ACME exception for bad Nonces
      class BadNonce < Bullion::Acme::Error
        def acme_type = "badNonce"
      end

      # ACME exception for bad/unsupported public keys
      class BadPublicKey < Bullion::Acme::Error
        def acme_type = "badPublicKey"
      end

      # ACME exception for invalid contacts in accounts
      class InvalidContact < Bullion::Acme::Error
        def acme_type = "invalidContact"
      end

      # ACME exception for invalid orders
      class InvalidOrder < Bullion::Acme::Error
        def acme_type = "invalidOrder"
      end

      # ACME exception for malformed requests
      class Malformed < Bullion::Acme::Error
        def acme_type = "malformed"
      end

      # ACME exception for unsupported contacts in accounts
      class UnsupportedContact < Bullion::Acme::Error
        def acme_type = "unsupportedContact"
      end

      # Non-standard exception for unsupported challenge types
      class UnsupportedChallengeType < Bullion::Acme::Error
        def acme_error = "urn:ietf:params:bullion:error:unsupportedChallengeType"
      end
    end
  end
end
