# frozen_string_literal: true

# End-to-end CA service tests for ECDSA keys (closes #16)
# Verifies that ECDSA account keys work through the full ACME flow:
# registration → order → authorization → challenge verification →
# finalization → cert download
RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  def app
    described_class
  end

  let(:account_email) { "ecdsa.e2e@example.com" }
  let(:ec_key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:ec_jwk) { ecdsa_public_key_hash(ec_key, "P-256") }

  let(:identifiers) do
    [{ "type" => "dns", "value" => "ecdsa-e2e.test.domain" }]
  end

  def build_protected_header(alg:, jwk:, nonce:, url:, kid: nil)
    header = { typ: "JWT", alg:, nonce:, url: }
    header[:kid] = kid if kid
    header[:jwk] = jwk unless kid
    header
  end

  def ecdsa_raw_sign(key, data)
    digest = OpenSSL::Digest.new("SHA256")
    raw_sig = key.sign(digest, data)
    seq = OpenSSL::ASN1.decode(raw_sig)
    big_ints = seq.value.map(&:value)
    bytes = (key.group.degree + 7) / 8
    r_val, s_val = big_ints.map { |v| v.to_s(2).rjust(bytes, "\x00") }
    acme_base64([r_val, s_val].join)
  end

  def acme_request(endpoint, payload, kid: nil, nonce: nil)
    get "/nonces"
    nonce ||= last_response.headers["Replay-Nonce"]

    header = build_protected_header(
      alg: "ES256", jwk: ec_jwk, kid:, nonce:, url: endpoint
    )
    encoded_protected = acme_base64(header.to_json)

    if payload == ""
      # Empty payload: signature is over "protected." (with trailing dot)
      signature = ecdsa_raw_sign(ec_key, "#{encoded_protected}.")
      encoded_payload = ""
    else
      encoded_payload = acme_base64(payload.to_json)
      sig_data = "#{encoded_protected}.#{encoded_payload}"
      signature = acme_sign(ec_key, sig_data, hash_alg: "SHA256")
    end

    { protected: encoded_protected, payload: encoded_payload, signature: }.to_json
  end

  def post_acme(endpoint, payload, kid: nil)
    body = acme_request(endpoint, payload, kid:)
    post endpoint, body, { "CONTENT_TYPE" => "application/jose+json" }
  end

  def register_ecdsa_account
    body = acme_request("/accounts", { contact: ["mailto:#{account_email}"] })
    post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }
    expect(last_response).to be_created
    parsed = JSON.parse(last_response.body)
    kid = last_response.headers["Location"]
    [parsed, kid]
  end

  def create_order(kid)
    body = acme_request("/orders", { identifiers: }, kid:)
    post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }
    expect(last_response).to be_created
    parsed = JSON.parse(last_response.body)
    [parsed, last_response.headers["Location"]]
  end

  def verify_challenge(kid)
    order = Bullion::Models::Order.last
    challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first

    post_acme("/challenges/#{challenge.id}", {}, kid:)
    expect(JSON.parse(last_response.body)["status"]).to eq("valid")
    order.reload
    expect(order.status).to eq("ready")
    [order, challenge]
  end

  def build_csr(domain, key)
    csr = OpenSSL::X509::Request.new
    csr.version = 0
    csr.subject = OpenSSL::X509::Name.new(
      [["CN", domain, OpenSSL::ASN1::UTF8STRING]]
    )
    csr.public_key = key

    factory = OpenSSL::X509::ExtensionFactory.new
    exts = [factory.create_extension("subjectAltName", "DNS:#{domain}")]
    attr_set = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
    csr.add_attribute(OpenSSL::X509::Attribute.new("extReq", attr_set))

    digest = key.is_a?(OpenSSL::PKey::EC) ? OpenSSL::Digest.new("SHA256") : nil
    csr.sign(key, digest)
    csr
  end

  def finalize_order(kid, order, csr)
    encoded_csr = Base64.urlsafe_encode64(csr.to_der)
    post_acme("/orders/#{order.id}/finalize", { csr: encoded_csr }, kid:)

    expect(last_response).to be_ok
    finalize_response = JSON.parse(last_response.body)
    expect(finalize_response["status"]).to eq("valid")
    expect(finalize_response).to include("certificate")
    finalize_response
  end

  def download_cert(kid, cert_url)
    cert_id = cert_url.split("/").last
    post_acme("/certificates/#{cert_id}", "", kid:)

    expect(last_response).to be_ok
    expect(last_response.headers["Content-Type"])
      .to eq("application/pem-certificate-chain")

    cert_pem = last_response.body.split("-----END CERTIFICATE-----\n").first
    OpenSSL::X509::Certificate.new("#{cert_pem}-----END CERTIFICATE-----\n")
  end

  context "with ECDSA P-256 account keys" do
    it "allows new client registrations" do
      parsed, _kid = register_ecdsa_account

      expect(parsed["status"]).to eq("valid")
      expect(parsed["contact"]).to eq(["mailto:#{account_email}"])
      expect(parsed["orders"]).to match(%r{^http://.+/accounts/[0-9]+/orders$})
    end

    it "allows submitting new orders" do
      _parsed, kid = register_ecdsa_account
      order_data, _url = create_order(kid)

      expect(order_data["status"]).to eq("pending")
      expect(order_data["authorizations"]).to be_an(Array)
      expect(order_data["authorizations"].size).to eq(1)
      expect(order_data["identifiers"]).to eq(identifiers)
      expect(order_data["finalize"])
        .to match(%r{http://.+/orders/[0-9]+/finalize})
    end

    it "allows retrieving authorizations and challenges" do
      _parsed, kid = register_ecdsa_account
      _order_data, _url = create_order(kid)

      order = Bullion::Models::Order.last
      auth = order.authorizations.first

      body = acme_request("/authorizations/#{auth.id}", {}, kid:)
      post "/authorizations/#{auth.id}", body,
           { "CONTENT_TYPE" => "application/jose+json" }

      parsed = JSON.parse(last_response.body)
      expect(parsed["status"]).to eq("pending")
      expect(parsed["identifier"]).to eq(identifiers.first)
      expect(parsed["challenges"]).to be_an(Array)
      expect(parsed["challenges"].size).to eq(2)

      types = parsed["challenges"].map { |c| c["type"] }
      expect(types).to include("http-01", "dns-01")
    end

    it "allows challenge verification" do
      _parsed, kid = register_ecdsa_account
      _order_data, _url = create_order(kid)

      order, challenge = verify_challenge(kid)

      auth = order.authorizations.first
      expect(auth.status).to eq("valid")
      expect(challenge.token).to be_a(String)
    end

    it "finalizes orders and downloads certificates with RSA cert keys" do
      _parsed, kid = register_ecdsa_account
      _order_data, _url = create_order(kid)

      order, _challenge = verify_challenge(kid)

      cert_key = OpenSSL::PKey::RSA.new(2048)
      csr = build_csr("ecdsa-e2e.test.domain", cert_key)

      finalize_response = finalize_order(kid, order, csr)
      cert = download_cert(kid, finalize_response["certificate"])

      expect(cert.subject.to_s).to end_with("/CN=ecdsa-e2e.test.domain")
      expect(cert.version).to eq(2) # x509v3

      # Verify the certificate is signed by the CA
      expect(cert.verify(Bullion.ca_key)).to be(true)

      extensions = cert.extensions.to_h { |ext| [ext.oid, ext.value] }
      expect(extensions["basicConstraints"]).to eq("CA:FALSE")
      expect(extensions["extendedKeyUsage"])
        .to eq("TLS Web Server Authentication")
      expect(extensions["subjectAltName"]).to eq("DNS:ecdsa-e2e.test.domain")
    end

    it "finalizes orders with ECDSA certificate keys" do
      _parsed, kid = register_ecdsa_account
      _order_data, _url = create_order(kid)

      order, _challenge = verify_challenge(kid)

      cert_ec_key = OpenSSL::PKey::EC.generate("prime256v1")
      csr = build_csr("ecdsa-e2e.test.domain", cert_ec_key)

      finalize_response = finalize_order(kid, order, csr)
      cert = download_cert(kid, finalize_response["certificate"])

      expect(cert.public_key).to be_a(OpenSSL::PKey::EC)
      expect(cert.subject.to_s).to end_with("/CN=ecdsa-e2e.test.domain")

      # Verify the certificate is signed by the CA
      expect(cert.verify(Bullion.ca_key)).to be(true)
    end
  end
end
