# frozen_string_literal: true

module Bullion
  # Common helper functions
  module Helpers
    # ACME-specific helper functions
    # The ownership and revocation enforcement work grew this module past
    # the default limit; the helpers are one cohesive ACME concern
    # rubocop:disable-next Metrics/ModuleLength
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
          alg = @header_data["alg"].downcase

          sig = if alg.start_with?("es")
                  ecdsa_sig_to_der(signature)
                elsif alg.start_with?("rs") || alg == "eddsa"
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

      # Ownership enforcement
      #
      # ACME resources are private to the account that created them. Requests
      # are authenticated via the JWS "kid" (see #parse_acme_jwt), and every
      # by-ID lookup below is scoped to that account: a resource that is
      # missing and a resource owned by someone else are both answered with a
      # 404, so an attacker cannot even learn that another account's order,
      # authorization, challenge, or certificate exists.

      # Returns the Order named by params[:id] when the authenticated account
      # owns it; nil when it is missing or belongs to a different account.
      def owned_order
        Models::Order.find_by(id: params[:id], account_id: @user.id)
      end

      # Returns the Authorization named by params[:id] when the authenticated
      # account owns its order; nil when it is missing or foreign-owned.
      def owned_authorization
        Models::Authorization.joins(:order)
                             .find_by(id: params[:id], orders: { account_id: @user.id })
      end

      # Returns the Challenge named by params[:id] when the authenticated
      # account owns the challenge's order; nil when missing or foreign-owned.
      def owned_challenge
        Models::Challenge.joins(authorization: :order)
                         .find_by(id: params[:id], orders: { account_id: @user.id })
      end

      # The identifiers whose authorizations this order has proven
      def validated_domains(order)
        order.authorizations.select(&:valid_status?).map { it.identifier["value"] }.sort
      end

      # Marks a just-validated challenge's authorization valid, and marks the
      # order ready once every one of its authorizations is valid: a single
      # valid challenge proves control of only one identifier, so a
      # multi-identifier order must not become finalizable early.
      def advance_validation!(challenge)
        authorization = challenge.authorization
        authorization.update!(status: "valid") unless authorization.valid_status?

        order = authorization.order
        return if order.ready_status?

        order.update!(status: "ready") if order.authorizations.all?(&:valid_status?)
      end

      # Halts with an RFC 7807 problem document for an ACME error
      def halt_acme_error(status, error_class, detail)
        content_type "application/problem+json"
        halt status, { type: error_class.new.acme_error, detail: }.to_json
      end

      # Refuses a request in the ACME not-found style (RFC 8555 section
      # 6.7): the same problem document answers for resources that do not
      # exist and resources owned by another account, so the existence of
      # someone else's order, authorization, challenge, or certificate is
      # never revealed.
      def halt_acme_not_found
        halt_acme_error(404, Bullion::Acme::Errors::Unauthorized, "Resource not found")
      end

      # Authenticates a revocation request per RFC 8555 section 7.6: a
      # "kid" in the protected header authenticates the signing account as
      # usual, while a bare "jwk" takes the emergency path — the JWS is
      # verified against the certificate's own public key, so only the
      # holder of the certificate's private key can produce such a request.
      # The header's jwk is a JOSE marker here, not the trusted key: a
      # valid signature under the certificate key proves possession, which
      # is what the spec requires.
      def authenticate_revocation!(cert)
        return parse_acme_jwt if extract_header_data["kid"]

        begin
          parse_acme_jwt(cert.public_key)
        rescue JWT::DecodeError, OpenSSL::PKey::PKeyError
          halt_acme_not_found
        end
      end

      # Whether the account may revoke the certificate record under RFC
      # 8555 section 7.6: either it is the account the certificate was
      # issued to, or it holds valid (non-deactivated) authorizations
      # covering every identifier in the certificate. The jwk path needs
      # no account check: its signature already proved possession of the
      # certificate's private key.
      def revocation_authorized?(account, record)
        return true if record.order&.account_id == account.id

        covered = Models::Authorization.joins(:order)
                                       .where(orders: { account_id: account.id },
                                              authorizations: { status: "valid" })
                                       .map { it.identifier["value"] }

        certificate_domains(record).all? { |domain| covered.include?(domain) }
      end

      # The identifiers a certificate covers (its subjectAltNames)
      def certificate_domains(record)
        domains = Array(record.alternate_names).map { it.delete_prefix("DNS:") }
        domains = record.order.domains if domains.empty? && record.order
        domains.sort
      end

      def acme_csr_valid?(order_csr)
        csr = order_csr.csr
        order = order_csr.order
        csr_attrs = extract_csr_attrs(csr)
        csr_sans = extract_csr_sans(csr_attrs)
        csr_domains = extract_csr_domains(csr_sans)
        csr_cn = cn_from_csr(csr) || csr_domains.first

        # Make sure the CSR has a valid public key
        raise Bullion::Acme::Errors::BadCsr unless csr.verify(csr.public_key)

        # The CA may only sign identifiers the order has proven control of:
        # the CSR's names must match the validated identifier set exactly, so
        # no extra or substituted name can make it into a certificate.
        validated = validated_domains(order)

        raise Bullion::Acme::Errors::BadCsr if csr_cn && !validated.include?(csr_cn)
        raise Bullion::Acme::Errors::BadCsr unless csr_domains.sort == validated

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
        if nb > Time.now + (7 * 86_400) || na > Time.now + Bullion.config.ca.cert_validity_duration
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
          # Only allow a configured domain itself or a proper subdomain of it;
          # the dot boundary stops "nottest.domain" from matching "test.domain"
          Bullion.config.ca.domains.none? do |configured|
            domain["value"] == configured || domain["value"].end_with?(".#{configured}")
          end
        end
      end

      # Builds the ACMEv2 order resource representation
      # @see https://tools.ietf.org/html/rfc8555#section-7.1.3
      def order_data(order)
        data = {
          status: order.status,
          expires: order.expires,
          notBefore: order.not_before,
          notAfter: order.not_after,
          identifiers: order.identifiers,
          authorizations: order.authorizations.map { uri("/authorizations/#{it.id}") },
          finalize: uri("/orders/#{order.id}/finalize")
        }

        data[:certificate] = uri("/certificates/#{order.certificate.id}") if order.valid_status?

        data
      end
    end
  end
end
