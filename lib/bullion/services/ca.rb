# frozen_string_literal: true

module Bullion
  module Services
    # ACME CA web service
    class CA < Service
      helpers Helpers::Acme
      helpers Helpers::Service
      helpers Helpers::Ssl

      before do
        Models::Nonce.clean_up! if rand(5) > 2 # randomly clean up
        @new_nonce = Models::Nonce.create.token
      end

      after do
        if request.options?
          @allowed_types ||= ["POST"]
          headers "Access-Control-Allow-Methods" => @allowed_types
        end
      end

      options "/directory" do
        @allowed_types = ["GET"]
        halt 200
      end

      options "/nonces" do
        @allowed_types = %w[HEAD GET]
        halt 200
      end

      options "/accounts" do
        halt 200
      end

      options "/accounts/:id" do
        halt 200
      end

      options "/accounts/:id/orders" do
        halt 200
      end

      options "/orders" do
        halt 200
      end

      options "/orders/:id" do
        halt 200
      end

      options "/orders/:id/finalize" do
        halt 200
      end

      options "/authorizations/:id" do
        halt 200
      end

      options "/challenges/:id" do
        halt 200
      end

      options "/certificates/:id" do
        halt 200
      end

      # Non-standard endpoint that returns the CA bundle for Bullion
      # Trusting this bundle should be sufficient to trust all Bullion-issued certs
      options "/cabundle" do
        @allowed_types = ["GET"]
        halt 200
      end

      # The directory is used to find all required URLs for the ACME endpoints
      # @see https://tools.ietf.org/html/rfc8555#section-7.1.1
      get "/directory" do
        content_type "application/json"

        {
          newNonce: uri("/nonces"),
          newAccount: uri("/accounts"),
          newOrder: uri("/orders"),
          revokeCert: uri("/revokecert"),
          keyChange: uri("/keychanges"),
          # non-standard entries:
          caBundle: uri("/cabundle")
        }.to_json
      end

      # Responds with Bullion's PEM-encoded public cert
      get "/cabundle" do
        expires 3600 * 48, :public, :must_revalidate
        content_type "application/x-pem-file"

        attachment "cabundle.pem"
        Bullion.ca_cert_file
      end

      # Retrieves a Nonce via a HEAD request
      # @see https://tools.ietf.org/html/rfc8555#section-7.2
      head "/nonces" do
        add_acme_headers @new_nonce, additional: { "Cache-Control" => "no-store" }

        halt 200
      end

      # Retrieves a Nonce via a GET request
      # @see https://tools.ietf.org/html/rfc8555#section-7.2
      get "/nonces" do
        add_acme_headers @new_nonce, additional: { "Cache-Control" => "no-store" }

        halt 204
      end

      # Creates an account or verifies that an account exists
      # @see https://tools.ietf.org/html/rfc8555#section-7.3
      post "/accounts" do
        header_data = JSON.parse(Base64.decode64(@json_body[:protected]))
        parse_acme_jwt(header_data["jwk"], validate_nonce: false)

        account_data_valid?(@payload_data)

        user = Models::Account.where(
          public_key: header_data["jwk"]
        ).first

        if @payload_data["onlyReturnExisting"]
          content_type "application/problem+json"
          unless user
            raise Bullion::Acme::Error::AccountDoesNotExist,
                  "onlyReturnExisting requested and account does not exist"
          end
        end

        user ||= Models::Account.new(public_key: header_data["jwk"])
        user.tos_agreed = true
        user.contacts = @payload_data["contact"]
        user.save

        content_type "application/json"
        add_acme_headers @new_nonce, additional: { "Location" => uri("/accounts/#{user.id}") }

        halt 201, {
          status: user.tos_agreed? ? "valid" : "pending",
          contact: user.contacts,
          orders: uri("/accounts/#{user.id}/orders")
        }.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 400, { type: e.acme_error, detail: e.message }.to_json
      end

      # Endpoint for updating accounts
      # @see https://tools.ietf.org/html/rfc8555#section-7.3.2
      post "/accounts/:id" do
        parse_acme_jwt

        unless params[:id] == @user.id
          content_type "application/json"
          add_acme_headers @new_nonce

          halt 403, { error: "Accounts can only view or update themselves" }.to_json
        end

        content_type "application/json"

        {
          status: "valid",
          orders: uri("/accounts/#{@user.id}/orders"),
          contact: @user.contacts
        }.to_json
      end

      post "/accounts/:id/orders" do
        parse_acme_jwt

        unless params[:id] == @user.id
          content_type "application/json"
          add_acme_headers @new_nonce

          halt 403, { error: "Accounts can only view or update themselves" }.to_json
        end

        content_type "application/json"
        add_acme_headers @new_nonce

        {
          orders: @user.orders.map { uri("/orders/#{it.id}") }
        }
      end

      # Endpoint for creating new orders
      # @see https://tools.ietf.org/html/rfc8555#section-7.4
      post "/orders" do
        parse_acme_jwt

        # Only identifiers of type "dns" are supported
        identifiers = @payload_data["identifiers"].select { it["type"] == "dns" }

        order_valid?(@payload_data)

        order = @user.start_order(
          identifiers:,
          not_before: @payload_data["notBefore"],
          not_after: @payload_data["notAfter"]
        )

        content_type "application/json"
        add_acme_headers @new_nonce, additional: { "Location" => uri("/orders/#{order.id}") }

        halt 201, {
          status: order.status,
          expires: order.expires,
          notBefore: order.not_before,
          notAfter: order.not_after,
          identifiers: order.identifiers,
          authorizations: order.authorizations.map { uri("/authorizations/#{it.id}") },
          finalize: uri("/orders/#{order.id}/finalize")
        }.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 400, { type: e.acme_error, detail: e.message }.to_json
      end

      # Retrieve existing Orders
      post "/orders/:id" do
        parse_acme_jwt

        content_type "application/json"
        add_acme_headers @new_nonce

        order = Models::Order.find(params[:id])

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

        data.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 400, { type: e.acme_error, detail: e.message }.to_json
      end

      # Submit an order for finalization/signing
      # @see https://tools.ietf.org/html/rfc8555#section-7.4
      post "/orders/:id/finalize" do
        parse_acme_jwt

        order = Models::Order.find(params[:id])

        content_type "application/json"
        add_acme_headers @new_nonce, additional: { "Location" => uri("/orders/#{order.id}") }

        order_csr = Models::OrderCsr.from_acme_request(order, @payload_data["csr"])

        unless acme_csr_valid?(order_csr)
          content_type "application/problem+json"
          halt 400, {
            type: Bullion::Acme::Errors::BadCsr.new.acme_error,
            detail: "CSR failed validation"
          }.to_json
        end

        cert_id = sign_csr(order_csr.csr, @user.contacts.first).last

        order.certificate_id = cert_id
        order.status = "valid"
        order.save

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

        data.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 422, { type: e.acme_error, detail: e.message }.to_json
      end

      # Shows that the client controls the account private key
      # @see https://tools.ietf.org/html/rfc8555#section-7.5
      post "/authorizations/:id" do
        parse_acme_jwt

        content_type "application/json"
        add_acme_headers @new_nonce

        authorization = Models::Authorization.find(params[:id])
        halt 404 unless authorization

        data = {
          status: authorization.status,
          expires: authorization.expires,
          identifier: authorization.identifier,
          challenges: authorization.challenges.map do |c|
            chash = {}
            chash[:type] = c.acme_type
            chash[:url] = uri("/challenges/#{c.id}")
            chash[:token] = c.token
            chash[:status] = c.status
            chash[:validated] = c.validated if c.valid_status?

            chash
          end
        }

        data.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 422, { type: e.acme_error, detail: e.message }.to_json
      end

      # Starts server verification of a challenge (either HTTP call or DNS lookup)
      # @see https://tools.ietf.org/html/rfc8555#section-7.5.1
      post "/challenges/:id" do
        parse_acme_jwt

        content_type "application/json"
        add_acme_headers @new_nonce

        challenge = Models::Challenge.find(params[:id])

        # Oddly enough, cert-manager uses a GET request for retrieving Challenge info
        challenge.client.attempt unless @json_body && @json_body[:payload] == ""

        challenge.reload

        data = {
          type: challenge.acme_type,
          status: challenge.status,
          expires: challenge.expires,
          token: challenge.token,
          url: uri("/challenges/#{challenge.id}")
        }

        if challenge.valid_status?
          data[:validated] = challenge.validated
          authorization = challenge.authorization
          authorization.update!(status: "valid") unless authorization.valid_status?
          order = authorization.order
          order.update!(status: "ready") unless order.ready_status?
        end

        add_link_relation("up", uri("/authorizations/#{challenge.authorization.id}"))

        data.to_json
      rescue Bullion::Acme::Error => e
        content_type "application/problem+json"
        halt 422, { type: e.acme_error, detail: e.message }.to_json
      end

      # Retrieves a signed certificate
      # @see https://tools.ietf.org/html/rfc8555#section-7.4.2
      post "/certificates/:id" do
        parse_acme_jwt
        add_acme_headers @new_nonce

        order = Models::Order.where(certificate_id: params[:id]).first
        if order&.valid_status?
          content_type "application/pem-certificate-chain"

          cert = Models::Certificate.find(params[:id])

          cert.data + Bullion.ca_cert_file
        else
          halt(422, { error: "Order not valid" }.to_json)
        end
      end
    end
  end
end
