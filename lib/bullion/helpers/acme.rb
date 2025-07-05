# frozen_string_literal: true

module Bullion
  # Common helper functions
  module Helpers
    # ACME-specific helper functions
    module Acme
      # Parses and verifies the incoming ACME JWT for authentication
      # @see https://tools.ietf.org/html/rfc8555#section-6.2
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/CyclomaticComplexity
      def parse_acme_jwt(key = nil, validate_nonce: true)
        @header_data = extract_header_data
        @payload_data = extract_payload_data
        signature = @json_body[:signature]

        # check nonce
        if validate_nonce
          nonce = Models::Nonce.where(token: @header_data["nonce"]).first
          raise Bullion::Acme::Errors::BadNonce unless nonce

          nonce.destroy
        end

        jwt_data = [
          @json_body[:protected],
          @json_body[:payload],
          @json_body[:signature]
        ].join(".")

        # Either use the provided key or find the current user's public key
        public_key = key || user_public_key

        # Convert the key to an OpenSSL-compatible key
        compat_public_key = openssl_compat(public_key)

        # Validate the payload was signed with the private key for the public key
        if @payload_data && @payload_data != ""
          JWT.decode(jwt_data, compat_public_key, true, { algorithm: @header_data["alg"] })
        else
          digest = digest_from_alg(@header_data["alg"])

          sig = if @header_data["alg"].downcase.start_with?("es")
                  ecdsa_sig_to_der(signature)
                elsif @header_data["alg"].downcase.start_with?("rs")
                  Base64.urlsafe_decode64(signature)
                end

          validated = compat_public_key.verify(
            digest,
            sig,
            "#{@json_body[:protected]}."
          )
          raise Bullion::Acme::Errors::Malformed unless validated
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity

      def extract_header_data
        JSON.parse(Base64.decode64(@json_body[:protected]))
      end

      def extract_payload_data
        if @json_body[:payload] && @json_body[:payload] != ""
          JSON.parse(Base64.decode64(@json_body[:payload]))
        else
          @json_body[:payload]
        end
      end

      def user_public_key
        @user = if @header_data["kid"]
                  user_id = @header_data["kid"].split("/").last
                  return unless user_id

                  Models::Account.find(user_id)
                else
                  Models::Account.where(public_key: @header_data["jwk"]).last
                end

        @user.public_key
      end

      # Validation helpers

      def account_data_valid?(hash)
        unless [true, false, nil].include?(hash["onlyReturnExisting"])
          raise Bullion::Acme::Errors::Malformed,
                "Invalid onlyReturnExisting: #{hash["onlyReturnExisting"]}"
        end

        unless hash["contact"].is_a?(Array)
          raise Bullion::Acme::Errors::InvalidContact,
                "Invalid contacts format: #{hash["contact"].class}, #{hash}"
        end

        unless hash["contact"].size.positive?
          raise Bullion::Acme::Errors::InvalidContact,
                "Empty contacts list"
        end

        # Contacts must be a valid email
        # TODO: find a better email verification approach
        unless hash["contact"].grep_v(/^mailto:[a-zA-Z0-9@.+-]{3,}/).empty?
          raise Bullion::Acme::Errors::UnsupportedContact
        end

        true
      end

      def acme_csr_valid?(order_csr)
        csr = order_csr.csr
        order = order_csr.order
        csr_attrs = extract_csr_attrs(csr)
        csr_sans = extract_csr_sans(csr_attrs)
        csr_domains = extract_csr_domains(csr_sans)
        csr_cn = cn_from_csr(csr)

        # Make sure the CSR has a valid public key
        raise Bullion::Acme::Errors::BadCsr unless csr.verify(csr.public_key)

        return false unless order.ready_status?
        raise Bullion::Acme::Errors::BadCsr unless csr_domains.include?(csr_cn)
        raise Bullion::Acme::Errors::BadCsr unless csr_domains.sort == order.domains.sort

        true
      end

      def order_valid?(hash)
        validate_order_nb_and_na(hash["notBefore"], hash["notAfter"])

        # Don't approve empty orders
        raise Bullion::Acme::Errors::InvalidOrder, "Empty order!" if hash["identifiers"].empty?

        order_domains = hash["identifiers"].select { it["type"] == "dns" }

        # Don't approve an order with identifiers that _aren't_ of type 'dns'
        unless hash["identifiers"] == order_domains
          raise Bullion::Acme::Errors::InvalidOrder, 'Only type "dns" allowed'
        end

        # Extract domains that end with something in our allowed domains list
        valid_domains = extract_valid_order_domains(order_domains)

        # Only allow configured domains...
        unless order_domains == valid_domains
          raise(
            Bullion::Acme::Errors::InvalidOrder,
            "Domains #{order_domains - valid_domains} not allowed"
          )
        end

        true
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def validate_order_nb_and_na(not_before, not_after)
        raise Bullion::Acme::Errors::Malformed if not_before && !not_before.is_a?(String)
        raise Bullion::Acme::Errors::Malformed if not_after && !not_after.is_a?(String)

        return unless not_before && not_after

        nb = Time.parse(not_before)
        na = Time.parse(not_after)

        # don't allow nonsense certs
        raise Bullion::Acme::Errors::InvalidOrder unless nb < na
        # don't allow far-future certs
        if nb > Time.now + (7 * 86_400) || na > Time.now + CERT_VALIDITY_DURATION
          raise Bullion::Acme::Errors::InvalidOrder
        end

        # don't allow really "old" certs
        raise Bullion::Acme::Errors::InvalidOrder if nb < Time.now - (14 * 86_400)
        # don't allow creating certs that are already expired
        raise Bullion::Acme::Errors::InvalidOrder if na <= Time.now
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def extract_valid_order_domains(order_domains)
        order_domains.reject do |domain|
          Bullion.config.ca.domains.none? { domain["value"].end_with?(it) }
        end
      end
    end
  end
end
