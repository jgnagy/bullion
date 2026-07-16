# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  context "when revoking certificates via /revokecert" do
    def app
      described_class
    end

    let(:account_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:account_email) { "revoke@example.com" }
    let(:cert_key) { OpenSSL::PKey::RSA.new(2048) }

    def rsa_raw_sign(key, data)
      digest = OpenSSL::Digest.new("SHA256")
      acme_base64(key.sign(digest, data))
    end

    def acme_request(endpoint, payload, kid: nil, nonce: nil)
      get "/nonces"
      nonce ||= last_response.headers["Replay-Nonce"]

      header = { typ: "JWT", alg: "RS256", nonce:, url: endpoint }
      if kid
        header[:kid] = kid
      else
        header[:jwk] = rsa_public_key_hash(account_key)
      end
      encoded_protected = acme_base64(header.to_json)

      if payload == ""
        signature = rsa_raw_sign(account_key, "#{encoded_protected}.")
        encoded_payload = ""
      else
        encoded_payload = acme_base64(payload.to_json)
        signature = acme_sign(account_key, "#{encoded_protected}.#{encoded_payload}")
      end

      { protected: encoded_protected, payload: encoded_payload, signature: }.to_json
    end

    def register_account
      body = acme_request("/accounts", { contact: ["mailto:#{account_email}"] })
      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }
      expect(last_response).to be_created
      last_response.headers["Location"]
    end

    # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    def sign_and_download_cert(kid, domain)
      order = Bullion::Models::Order.last

      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new(
        [["CN", domain, OpenSSL::ASN1::UTF8STRING]]
      )
      csr.public_key = cert_key

      factory = OpenSSL::X509::ExtensionFactory.new
      exts = [factory.create_extension("subjectAltName", "DNS:#{domain}")]
      attr_set = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
      csr.add_attribute(OpenSSL::X509::Attribute.new("extReq", attr_set))
      csr.sign(cert_key, OpenSSL::Digest.new("SHA256"))

      encoded_csr = Base64.urlsafe_encode64(csr.to_der)
      body = acme_request("/orders/#{order.id}/finalize", { csr: encoded_csr }, kid:)
      post "/orders/#{order.id}/finalize", body,
           { "CONTENT_TYPE" => "application/jose+json" }
      expect(last_response).to be_ok

      cert_url = JSON.parse(last_response.body)["certificate"]
      cert_id = cert_url.split("/").last

      body = acme_request("/certificates/#{cert_id}", "", kid:)
      post "/certificates/#{cert_id}", body,
           { "CONTENT_TYPE" => "application/jose+json" }
      expect(last_response).to be_ok

      cert_pem = last_response.body.split("-----END CERTIFICATE-----\n").first
      cert = OpenSSL::X509::Certificate.new("#{cert_pem}-----END CERTIFICATE-----\n")
      [cert, cert_id]
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength

    it "returns 200 OK for OPTIONS requests for /revokecert" do
      options "/revokecert"
      expect(last_response).to be_ok
    end

    it "successfully revokes a valid certificate" do
      kid = register_account
      domain = "revoke.test.domain"

      # Create order and verify challenge
      body = acme_request("/orders",
                          { identifiers: [{ "type" => "dns", "value" => domain }] }, kid:)
      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      order = Bullion::Models::Order.last
      challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first
      body = acme_request("/challenges/#{challenge.id}", {}, kid:)
      post "/challenges/#{challenge.id}", body,
           { "CONTENT_TYPE" => "application/jose+json" }
      order.reload

      cert, _cert_id = sign_and_download_cert(kid, domain)

      # Revoke the cert
      cert_der = cert.to_der
      body = acme_request("/revokecert",
                          { certificate: Base64.urlsafe_encode64(cert_der) }, kid:)
      post "/revokecert", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_ok
      expect(last_response.body).to be_empty

      # Verify the certificate is marked as revoked in the DB
      record = Bullion::Models::Certificate.where(data: cert.to_pem).first
      expect(record).to be_revoked
    end

    it "rejects revoking an already-revoked certificate" do
      kid = register_account
      domain = "already.test.domain"

      # Create order and verify challenge
      body = acme_request("/orders",
                          { identifiers: [{ "type" => "dns", "value" => domain }] }, kid:)
      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      order = Bullion::Models::Order.last
      challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first
      body = acme_request("/challenges/#{challenge.id}", {}, kid:)
      post "/challenges/#{challenge.id}", body,
           { "CONTENT_TYPE" => "application/jose+json" }
      order.reload

      cert, _cert_id = sign_and_download_cert(kid, domain)

      # First revocation
      cert_der = cert.to_der
      body = acme_request("/revokecert",
                          { certificate: Base64.urlsafe_encode64(cert_der) }, kid:)
      post "/revokecert", body, { "CONTENT_TYPE" => "application/jose+json" }
      expect(last_response).to be_ok

      # Second revocation attempt
      body = acme_request("/revokecert",
                          { certificate: Base64.urlsafe_encode64(cert_der) }, kid:)
      post "/revokecert", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to eq("application/problem+json")

      parsed = JSON.parse(last_response.body)
      expect(parsed["type"]).to eq("urn:ietf:params:acme:error:alreadyRevoked")
    end

    it "rejects revoking a non-existent certificate" do
      kid = register_account

      # Create a self-signed cert that was never issued by this CA
      fake_key = OpenSSL::PKey::RSA.new(2_048)
      fake_cert = OpenSSL::X509::Certificate.new
      fake_cert.version = 2
      fake_cert.serial = 12_345
      fake_cert.subject = OpenSSL::X509::Name.new(
        [["CN", "fake.test.domain", OpenSSL::ASN1::UTF8STRING]]
      )
      fake_cert.issuer = fake_cert.subject
      fake_cert.public_key = fake_key.public_key
      fake_cert.not_before = Time.now
      fake_cert.not_after = Time.now + 3600
      fake_cert.sign(fake_key, OpenSSL::Digest.new("SHA256"))

      cert_der = fake_cert.to_der
      body = acme_request("/revokecert",
                          { certificate: Base64.urlsafe_encode64(cert_der) }, kid:)
      post "/revokecert", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to eq("application/problem+json")

      parsed = JSON.parse(last_response.body)
      expect(parsed["type"]).to eq("urn:ietf:params:acme:error:badCertificate")
    end
  end
end
