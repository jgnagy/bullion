# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  def app
    described_class
  end

  # Use a fresh RSA key per test to avoid unique constraint conflicts
  # with other spec files that share the memoized rsa_key helper.
  let(:account_key) { OpenSSL::PKey::RSA.new(2048) }

  let(:account_email) { "negative_test@example.com" }

  def register_account(key: account_key, email: account_email)
    jwk = {
      typ: "JWT",
      alg: "RS256",
      jwk: rsa_public_key_hash(key)
    }.to_json
    encoded_jwk = acme_base64(jwk)
    payload = {
      contact: ["mailto:#{email}"]
    }.to_json
    encoded_payload = acme_base64(payload)
    signature_data = "#{encoded_jwk}.#{encoded_payload}"

    body = {
      protected: encoded_jwk,
      payload: encoded_payload,
      signature: acme_sign(key, signature_data)
    }.to_json

    post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

    expect(last_response).to be_created
    JSON.parse(last_response.body)
  end

  def submit_order(key:, kid:, identifiers: [])
    get "/nonces"
    nonce = last_response.headers["Replay-Nonce"]

    jwk = {
      typ: "JWT",
      alg: "RS256",
      kid:,
      nonce:,
      url: "/orders"
    }.to_json
    encoded_jwk = acme_base64(jwk)
    payload = { identifiers: }.to_json
    encoded_payload = acme_base64(payload)
    signature_data = "#{encoded_jwk}.#{encoded_payload}"

    body = {
      protected: encoded_jwk,
      payload: encoded_payload,
      signature: acme_sign(key, signature_data)
    }.to_json

    post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }
  end

  # rubocop:disable-next Metrics/AbcSize,Metrics/MethodLength
  def verify_challenge(kid:, order_id:, authz_index: 0, nonce: nil)
    get "/nonces"
    nonce ||= last_response.headers["Replay-Nonce"]

    order = Bullion::Models::Order.find(order_id)
    authz = order.authorizations[authz_index]
    challenge = authz.challenges.where(acme_type: "http-01").first

    jwk = {
      typ: "JWT",
      alg: "RS256",
      kid:,
      nonce:,
      url: "/challenges/#{challenge.id}"
    }.to_json
    encoded_jwk = acme_base64(jwk)
    payload = "{}".to_json
    encoded_payload = acme_base64(payload)
    signature_data = "#{encoded_jwk}.#{encoded_payload}"

    body = {
      protected: encoded_jwk,
      payload: encoded_payload,
      signature: acme_sign(account_key, signature_data)
    }.to_json

    post "/challenges/#{challenge.id}", body, { "CONTENT_TYPE" => "application/jose+json" }

    order.reload
    [order, challenge]
  end

  def build_cert_csr(domain, key)
    cert_req = OpenSSL::X509::Request.new
    cert_req.version = 0
    cert_req.subject = OpenSSL::X509::Name.new(
      [["CN", domain, OpenSSL::ASN1::UTF8STRING]]
    )
    cert_req.public_key = key

    factory = OpenSSL::X509::ExtensionFactory.new
    exts = [factory.create_extension("subjectAltName", "DNS:#{domain}")]
    attr_set = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
    cert_req.add_attribute(OpenSSL::X509::Attribute.new("extReq", attr_set))

    digest = key.is_a?(OpenSSL::PKey::EC) ? OpenSSL::Digest.new("SHA256") : nil
    cert_req.sign(key, digest)
    cert_req
  end

  # Builds a CSR whose CN is the first domain and whose SANs cover them all
  def build_multi_domain_csr(domains, key)
    cert_req = OpenSSL::X509::Request.new
    cert_req.version = 0
    cert_req.subject = OpenSSL::X509::Name.new(
      [["CN", domains.first, OpenSSL::ASN1::UTF8STRING]]
    )
    cert_req.public_key = key

    factory = OpenSSL::X509::ExtensionFactory.new
    sans = domains.map { "DNS:#{it}" }.join(",")
    exts = [factory.create_extension("subjectAltName", sans)]
    attr_set = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
    cert_req.add_attribute(OpenSSL::X509::Attribute.new("extReq", attr_set))

    cert_req.sign(key, OpenSSL::Digest.new("SHA256"))
    cert_req
  end

  # rubocop:disable-next Metrics/MethodLength
  def finalize_order(kid:, order_id:, csr:)
    encoded_csr = Base64.urlsafe_encode64(csr.to_der)

    get "/nonces"
    nonce = last_response.headers["Replay-Nonce"]

    jwk = {
      typ: "JWT",
      alg: "RS256",
      kid:,
      nonce:,
      url: "/orders/#{order_id}/finalize"
    }.to_json
    encoded_jwk = acme_base64(jwk)
    payload = { csr: encoded_csr }.to_json
    encoded_payload = acme_base64(payload)
    signature_data = "#{encoded_jwk}.#{encoded_payload}"

    body = {
      protected: encoded_jwk,
      payload: encoded_payload,
      signature: acme_sign(account_key, signature_data)
    }.to_json

    post "/orders/#{order_id}/finalize", body,
         { "CONTENT_TYPE" => "application/jose+json" }
  end

  context "with negative test cases" do
    it "rejects orders with invalid domains" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:, identifiers: [{ "type" => "dns",
                                                           "value" => "evil.notallowed.com" }])

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects orders with empty identifiers" do
      register_account
      kid = last_response.headers["Location"]

      get "/nonces"
      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        kid:,
        nonce:,
        url: "/orders"
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = { identifiers: [] }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects orders with non-dns identifiers" do
      register_account
      kid = last_response.headers["Location"]

      get "/nonces"
      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        kid:,
        nonce:,
        url: "/orders"
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = { identifiers: [{ "type" => "ip",
                                  "value" => "192.0.2.1" }] }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "allows orders for an exact configured domain" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:,
                   identifiers: [{ "type" => "dns", "value" => "test.domain" }])

      expect(last_response).to be_created
    end

    it "allows orders for subdomains of a configured domain" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:,
                   identifiers: [{ "type" => "dns", "value" => "foo.test.domain" }])

      expect(last_response).to be_created
    end

    it "rejects orders for domains that merely end with a configured domain" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:,
                   identifiers: [{ "type" => "dns", "value" => "nottest.domain" }])

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects orders for proper suffixes of a configured domain" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:,
                   identifiers: [{ "type" => "dns", "value" => "est.domain" }])

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects orders for domains unrelated to any configured domain" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:,
                   identifiers: [{ "type" => "dns", "value" => "other.domain" }])

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects account registration with contact as a non-array" do
      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key)
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = { contact: "not-an-array" }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidContact")
    end

    it "rejects account registration with empty contacts" do
      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key)
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = { contact: [] }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidContact")
    end

    it "rejects certificate download for non-existent order" do
      register_account
      kid = last_response.headers["Location"]

      get "/nonces"
      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        kid:,
        nonce:,
        url: "/certificates/999999"
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = "{}".to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/certificates/999999", body,
           { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(422)
    end

    it "rejects challenge verification for non-existent challenge" do
      register_account
      kid = last_response.headers["Location"]

      get "/nonces"
      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        kid:,
        nonce:,
        url: "/challenges/999999"
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = "{}".to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      # Challenge lookups are scoped to the authenticated account, so a
      # missing challenge answers with a 404 — exactly like a challenge
      # that belongs to a different account (no existence leak).
      post "/challenges/999999", body,
           { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to be_empty
    end

    it "rejects orders with notAfter beyond the maximum validity duration" do
      register_account
      kid = last_response.headers["Location"]

      get "/nonces"
      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        kid:,
        nonce:,
        url: "/orders"
      }.to_json
      encoded_jwk = acme_base64(jwk)

      now = Time.now
      payload = {
        identifiers: [{ "type" => "dns", "value" => "good.test.domain" }],
        notBefore: (now + 86_400).iso8601,
        notAfter: (now + (90 * 24 * 60 * 60) + 86_400).iso8601
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:invalidOrder")
    end

    it "rejects finalization with CSR for wrong domain" do
      register_account
      kid = last_response.headers["Location"]

      # Create order for good.test.domain
      submit_order(key: account_key, kid:, identifiers: [{ "type" => "dns",
                                                           "value" => "good.test.domain" }])
      expect(last_response).to be_created
      finalize_url = JSON.parse(last_response.body)["finalize"]
      order_id = finalize_url.match(%r{/orders/(\d+)/finalize})[1].to_i

      # Verify challenge
      order, = verify_challenge(kid:, order_id:)
      expect(order.status).to eq("ready")

      # Build a CSR for wrong domain (valid CA domain but not matching order)
      cert_key = OpenSSL::PKey::RSA.new(2048)
      csr = build_cert_csr("wrong.test.domain", cert_key)

      finalize_order(kid:, order_id: order.id, csr:)

      expect(last_response.status).to eq(422)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      # BadCsr error type maps to "badCSR" in the ACME error class
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:badCSR")
    end

    it "rejects finalization with a CSR carrying an extra identifier" do
      register_account
      kid = last_response.headers["Location"]

      submit_order(key: account_key, kid:, identifiers: [{ "type" => "dns",
                                                           "value" => "good.test.domain" }])
      expect(last_response).to be_created
      finalize_url = JSON.parse(last_response.body)["finalize"]
      order_id = finalize_url.match(%r{/orders/(\d+)/finalize})[1].to_i

      order, = verify_challenge(kid:, order_id:)
      expect(order.status).to eq("ready")

      # The CSR asks for a second name the order never validated
      cert_key = OpenSSL::PKey::RSA.new(2048)
      csr = build_multi_domain_csr(["good.test.domain", "extra.test.domain"], cert_key)

      cert_count = Bullion::Models::Certificate.count
      finalize_order(kid:, order_id: order.id, csr:)

      expect(last_response.status).to eq(422)
      expect(last_response.headers["Content-Type"]).to \
        eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to \
        eq("urn:ietf:params:acme:error:badCSR")

      # Refusal must be side-effect free: no certificate was signed
      expect(order.reload.certificate_id).to be_nil
      expect(Bullion::Models::Certificate.count).to eq(cert_count)
    end

    context "with multi-identifier orders" do
      def order_with_two_domains
        register_account
        kid = last_response.headers["Location"]

        submit_order(key: account_key, kid:, identifiers: [
                       { "type" => "dns", "value" => "first.test.domain" },
                       { "type" => "dns", "value" => "second.test.domain" }
                     ])
        expect(last_response).to be_created
        finalize_url = JSON.parse(last_response.body)["finalize"]
        order_id = finalize_url.match(%r{/orders/(\d+)/finalize})[1].to_i

        [kid, Bullion::Models::Order.find(order_id)]
      end

      it "does not mark an order ready until every authorization is valid" do
        kid, order = order_with_two_domains

        # Only the first identifier's challenge has been validated
        verify_challenge(kid:, order_id: order.id)

        expect(order.reload.status).to eq("pending")
      end

      it "refuses to finalize with an unvalidated authorization" do
        kid, order = order_with_two_domains
        verify_challenge(kid:, order_id: order.id)

        cert_key = OpenSSL::PKey::RSA.new(2048)
        csr = build_multi_domain_csr(["first.test.domain", "second.test.domain"], cert_key)

        finalize_order(kid:, order_id: order.id, csr:)

        expect(last_response.status).to eq(403)
        expect(last_response.headers["Content-Type"]).to \
          eq("application/problem+json")

        parsed_body = JSON.parse(last_response.body)
        expect(parsed_body["type"]).to \
          eq("urn:ietf:params:acme:error:orderNotReady")

        expect(order.reload.certificate_id).to be_nil
      end

      it "finalizes once every authorization is valid, covering both names" do
        kid, order = order_with_two_domains

        verify_challenge(kid:, order_id: order.id)
        verify_challenge(kid:, order_id: order.id, authz_index: 1)

        expect(order.reload.status).to eq("ready")

        cert_key = OpenSSL::PKey::RSA.new(2048)
        csr = build_multi_domain_csr(["first.test.domain", "second.test.domain"], cert_key)
        finalize_order(kid:, order_id: order.id, csr:)

        expect(last_response).to be_ok
        parsed_body = JSON.parse(last_response.body)
        expect(parsed_body["status"]).to eq("valid")
        expect(parsed_body).to include("certificate")

        cert_id = parsed_body["certificate"].split("/").last
        cert_pem = Bullion::Models::Certificate.find(cert_id).data
        cert = OpenSSL::X509::Certificate.new(cert_pem)
        san = cert.extensions.find { it.oid == "subjectAltName" }.value
        expect(san).to include("DNS:first.test.domain")
        expect(san).to include("DNS:second.test.domain")
      end
    end

    context "when finalizing an order that is not ready" do
      def order_with_id(domain: "good.test.domain")
        register_account
        kid = last_response.headers["Location"]

        submit_order(key: account_key, kid:, identifiers: [{ "type" => "dns",
                                                             "value" => domain }])
        expect(last_response).to be_created
        finalize_url = JSON.parse(last_response.body)["finalize"]
        order_id = finalize_url.match(%r{/orders/(\d+)/finalize})[1].to_i
        [kid, order_id]
      end

      it "is idempotent when the order is already valid" do
        kid, order_id = order_with_id
        order, = verify_challenge(kid:, order_id:)
        expect(order.status).to eq("ready")

        cert_key = OpenSSL::PKey::RSA.new(2048)
        csr = build_cert_csr("good.test.domain", cert_key)

        finalize_order(kid:, order_id: order.id, csr:)
        expect(last_response).to be_ok
        first_body = JSON.parse(last_response.body)
        expect(first_body["status"]).to eq("valid")
        expect(first_body).to include("certificate")

        finalize_order(kid:, order_id: order.id, csr:)

        expect(last_response).to be_ok
        expect(last_response.headers["Content-Type"]).to eq("application/json")
        second_body = JSON.parse(last_response.body)
        expect(second_body["status"]).to eq("valid")
        expect(second_body["certificate"]).to eq(first_body["certificate"])
      end

      it "returns 403 orderNotReady when the order is pending" do
        kid, order_id = order_with_id

        cert_key = OpenSSL::PKey::RSA.new(2048)
        csr = build_cert_csr("good.test.domain", cert_key)

        finalize_order(kid:, order_id:, csr:)

        expect(last_response.status).to eq(403)
        expect(last_response.headers["Content-Type"]).to \
          eq("application/problem+json")
        parsed_body = JSON.parse(last_response.body)
        expect(parsed_body["type"]).to \
          eq("urn:ietf:params:acme:error:orderNotReady")
      end
    end
  end
end
