# frozen_string_literal: true

module Bullion
  module Acme
    # ACME protocol errors super class
    class Error < Bullion::Error
      # @see https://tools.ietf.org/html/rfc8555#section-6.7
      # RFC 8555 section 6.7 says the ACME URN namespace must not be used for
      # unregistered error types, so the generic fallback is the registered
      # "serverInternal" type.
      def acme_type
        "serverInternal"
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

      # ACME exception for unidentifiable certificates, e.g. a revocation
      # request for a certificate this CA never issued. RFC 8555 section 6.7
      # and the IANA ACME Error Types registry have no dedicated type for
      # this situation, so this maps to the registered generic error type.
      class BadCertificate < Bullion::Acme::Error
        def acme_type = "serverInternal"
      end

      # ACME exception for already-revoked certificates
      class AlreadyRevoked < Bullion::Acme::Error
        def acme_type = "alreadyRevoked"
      end

      # ACME exception for invalid contacts in accounts
      class InvalidContact < Bullion::Acme::Error
        def acme_type = "invalidContact"
      end

      # ACME exception for malformed requests
      class Malformed < Bullion::Acme::Error
        def acme_type = "malformed"
      end

      # ACME exception for identifiers the server will not issue
      # certificates for
      class RejectedIdentifier < Bullion::Acme::Error
        def acme_type = "rejectedIdentifier"
      end

      # ACME exception for unsupported identifier types
      class UnsupportedIdentifier < Bullion::Acme::Error
        def acme_type = "unsupportedIdentifier"
      end

      # ACME exception for orders that aren't ready to be finalized
      class OrderNotReady < Bullion::Acme::Error
        def acme_type = "orderNotReady"
      end

      # ACME exception for unsupported contacts in accounts
      class UnsupportedContact < Bullion::Acme::Error
        def acme_type = "unsupportedContact"
      end

      # ACME exception for requests the account is not authorized to make.
      # Also used for not-found-style refusals: the ACME registry has no
      # generic "notFound" problem type, and "unauthorized" is its closest
      # entry ("a request for an identifier the account is not authorized
      # to manage"); the identical response for missing and foreign-owned
      # resources keeps the two cases indistinguishable.
      class Unauthorized < Bullion::Acme::Error
        def acme_type = "unauthorized"
      end

      # Non-standard exception for unsupported challenge types. Per RFC 8555
      # section 6.7, non-registered error types must not use the ACME URN
      # namespace, so this uses the Bullion-specific one.
      class UnsupportedChallengeType < Bullion::Acme::Error
        def acme_error = "urn:ietf:params:bullion:error:unsupportedChallengeType"
      end
    end
  end
end
