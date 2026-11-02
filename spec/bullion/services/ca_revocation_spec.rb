# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  def app
    described_class
  end

  # Fresh keys per example: accounts are unique on their key hash, and a
  # persistent test database would otherwise collide across repeated runs
  let(:issuer_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:rescuer_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:outsider_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:partial_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:issuer_email) { "issuer@example.com" }
  let(:rescuer_email) { "rescuer@example.com" }
  let(:outsider_email) { "outsider@example.com" }
  let(:partial_email) { "partial@example.com" }
  let(:domain) { "revocable.test.domain" }
  let(:cert_key) { OpenSSL::PKey::RSA.new(2048) }

  def acme_request(endpoint, payload, key:, kid: nil)
    get "/nonces"
    nonce = last_response.headers["Replay-Nonce"]

    header = { typ: "JWT", alg: "RS256", nonce:, url: endpoint }
    if kid
      header[:kid] = kid
    else
      header[:jwk] = rsa_public_key_hash(key)
    end
    encoded_protected = acme_base64(header.to_json)

    if payload == ""
      digest = OpenSSL::Digest.new("SHA256")
      signature = acme_base64(key.sign(digest, "#{encoded_protected}."))
      encoded_payload = ""
    else
      encoded_payload = acme_base64(payload.to_json)
      signature = acme_sign(key, "#{encoded_protected}.#{encoded_payload}")
    end

    { protected: encoded_protected, payload: encoded_payload, signature: }.to_json
  end

  def post_acme(endpoint, body)
    post endpoint, body, { "CONTENT_TYPE" => "application/jose+json" }
  end

  def register_account(key:, email:)
    body = acme_request("/accounts", { contact: ["mailto:#{email}"] }, key:)
    post_acme("/accounts", body)
    expect(last_response).to be_created
    last_response.headers["Location"]
  end

  # Builds a CSR whose CN is the first domain and whose SANs cover them all
  def build_cert_csr(domains, key)
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

  def create_order(kid:, key:, domains:)
    identifiers = domains.map { { "type" => "dns", "value" => it } }
    body = acme_request("/orders", { identifiers: }, key:, kid:)
    post_acme("/orders", body)
    expect(last_response).to be_created

    finalize_url = JSON.parse(last_response.body)["finalize"]
    order_id = finalize_url.match(%r{/orders/(\d+)/finalize})[1].to_i
    Bullion::Models::Order.find(order_id)
  end

  def trigger_challenge(challenge, kid:, key:)
    body = acme_request("/challenges/#{challenge.id}", {}, key:, kid:)
    post_acme("/challenges/#{challenge.id}", body)
  end

  def validate_order(kid:, key:, order:)
    order.authorizations.each do |authorization|
      challenge = authorization.challenges.where(acme_type: "http-01").first
      trigger_challenge(challenge, kid:, key:)
      expect(last_response).to be_ok
    end

    order.reload
  end

  # rubocop:disable-next Metrics/AbcSize
  def issue_certificate(kid:, key:, order:, domains:)
    csr = build_cert_csr(domains, cert_key)
    body = acme_request("/orders/#{order.id}/finalize",
                        { csr: Base64.urlsafe_encode64(csr.to_der) }, key:, kid:)
    post_acme("/orders/#{order.id}/finalize", body)
    expect(last_response).to be_ok

    cert_id = JSON.parse(last_response.body)["certificate"].split("/").last

    body = acme_request("/certificates/#{cert_id}", "", key:, kid:)
    post_acme("/certificates/#{cert_id}", body)
    expect(last_response).to be_ok

    cert_pem = last_response.body.split("-----END CERTIFICATE-----\n").first
    [OpenSSL::X509::Certificate.new("#{cert_pem}-----END CERTIFICATE-----\n"), cert_id]
  end

  def revoke_with_account(cert, key:, kid:)
    body = acme_request("/revokecert",
                        { certificate: Base64.urlsafe_encode64(cert.to_der) },
                        key:, kid:)
    post_acme("/revokecert", body)
  end

  def revoke_with_certificate_key(cert, key:)
    body = acme_request("/revokecert",
                        { certificate: Base64.urlsafe_encode64(cert.to_der) },
                        key:)
    post_acme("/revokecert", body)
  end

  # Refusals answer with the not-found problem document and leave the
  # certificate untouched; the returned triple identifies the exact
  # response for indistinguishability comparisons
  def expect_refused_without_revocation(cert)
    expect(last_response.status).to eq(404)
    expect(last_response.headers["Content-Type"]).to eq("application/problem+json")
    expect_unauthorized_problem_document
    expect_certificate_not_revoked(cert)

    [last_response.status, last_response.headers["Content-Type"], last_response.body]
  end

  def expect_unauthorized_problem_document
    parsed_body = JSON.parse(last_response.body)
    expect(parsed_body["type"]).to eq("urn:ietf:params:acme:error:unauthorized")
    expect(parsed_body["detail"]).to be_a(String)
  end

  def expect_certificate_not_revoked(cert)
    record = Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)
    expect(record).not_to be_revoked
    expect(record.revoked_at).to be_nil
  end

  context "when accepting revocations per RFC 8555 section 7.6" do
    it "accepts revocation from the issuing account" do
      issuer_kid = register_account(key: issuer_key, email: issuer_email)
      order = create_order(kid: issuer_kid, key: issuer_key, domains: [domain])
      validate_order(kid: issuer_kid, key: issuer_key, order:)
      cert, = issue_certificate(kid: issuer_kid, key: issuer_key, order:, domains: [domain])

      revoke_with_account(cert, key: issuer_key, kid: issuer_kid)

      expect(last_response).to be_ok
      expect(Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)).to be_revoked
    end

    it "accepts revocation from an account holding all authorizations" do
      issuer_kid = register_account(key: issuer_key, email: issuer_email)
      rescuer_kid = register_account(key: rescuer_key, email: rescuer_email)

      order = create_order(kid: issuer_kid, key: issuer_key, domains: [domain])
      validate_order(kid: issuer_kid, key: issuer_key, order:)
      cert, = issue_certificate(kid: issuer_kid, key: issuer_key, order:, domains: [domain])

      # The second account validates its own authorization for the identifier
      rescuer_order = create_order(kid: rescuer_kid, key: rescuer_key, domains: [domain])
      validate_order(kid: rescuer_kid, key: rescuer_key, order: rescuer_order)

      revoke_with_account(cert, key: rescuer_key, kid: rescuer_kid)

      expect(last_response).to be_ok
      expect(Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)).to be_revoked
    end

    it "accepts revocation signed with the certificate's private key" do
      issuer_kid = register_account(key: issuer_key, email: issuer_email)
      order = create_order(kid: issuer_kid, key: issuer_key, domains: [domain])
      validate_order(kid: issuer_kid, key: issuer_key, order:)
      cert, = issue_certificate(kid: issuer_kid, key: issuer_key, order:, domains: [domain])

      # No account is referenced: the JWS carries the certificate key as its jwk
      revoke_with_certificate_key(cert, key: cert_key)

      expect(last_response).to be_ok
      expect(Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)).to be_revoked
    end

    it "refuses wrong keys and claim-less accounts identically" do
      issuer_kid = register_account(key: issuer_key, email: issuer_email)
      outsider_kid = register_account(key: outsider_key, email: outsider_email)

      order = create_order(kid: issuer_kid, key: issuer_key, domains: [domain])
      validate_order(kid: issuer_kid, key: issuer_key, order:)
      cert, = issue_certificate(kid: issuer_kid, key: issuer_key, order:, domains: [domain])

      # A private key that is not the certificate's key
      wrong_key = OpenSSL::PKey::RSA.new(2048)
      revoke_with_certificate_key(cert, key: wrong_key)
      wrong_key_refusal = expect_refused_without_revocation(cert)

      # An account with no authorizations for the certificate's identifiers
      revoke_with_account(cert, key: outsider_key, kid: outsider_kid)
      outsider_refusal = expect_refused_without_revocation(cert)

      expect(wrong_key_refusal).to eq(outsider_refusal)
    end

    it "refuses an account covering only some of the certificate's identifiers" do
      issuer_kid = register_account(key: issuer_key, email: issuer_email)
      partial_kid = register_account(key: partial_key, email: partial_email)

      domains = ["first.test.domain", "second.test.domain"]
      order = create_order(kid: issuer_kid, key: issuer_key, domains:)
      validate_order(kid: issuer_kid, key: issuer_key, order:)
      cert, = issue_certificate(kid: issuer_kid, key: issuer_key, order:, domains:)

      # The account has validated only the first of the two identifiers
      partial_order = create_order(kid: partial_kid, key: partial_key, domains: [domains.first])
      validate_order(kid: partial_kid, key: partial_key, order: partial_order)

      revoke_with_account(cert, key: partial_key, kid: partial_kid)

      expect_refused_without_revocation(cert)
    end
  end
end
