# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  def app
    described_class
  end

  # Fresh keys per example: accounts are unique on their key hash, and a
  # persistent test database would otherwise collide across repeated runs
  let(:attacker_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:victim_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:attacker_email) { "attacker@example.com" }
  let(:victim_email) { "victim@example.com" }
  let(:victim_domain) { "victim.test.domain" }
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

    cert_req.sign(key, OpenSSL::Digest.new("SHA256"))
    cert_req
  end

  def create_order(kid:, key:, domain:)
    payload = { identifiers: [{ "type" => "dns", "value" => domain }] }
    body = acme_request("/orders", payload, key:, kid:)
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

  def finalize_order(kid:, key:, order:, domain:)
    csr = build_cert_csr(domain, cert_key)
    body = acme_request("/orders/#{order.id}/finalize",
                        { csr: Base64.urlsafe_encode64(csr.to_der) }, key:, kid:)
    post_acme("/orders/#{order.id}/finalize", body)
  end

  # rubocop:disable-next Metrics/AbcSize
  def issue_certificate(kid:, key:, order:, domain:)
    finalize_order(kid:, key:, order:, domain:)
    expect(last_response).to be_ok

    cert_id = JSON.parse(last_response.body)["certificate"].split("/").last

    body = acme_request("/certificates/#{cert_id}", "", key:, kid:)
    post_acme("/certificates/#{cert_id}", body)
    expect(last_response).to be_ok

    cert_pem = last_response.body.split("-----END CERTIFICATE-----\n").first
    [OpenSSL::X509::Certificate.new("#{cert_pem}-----END CERTIFICATE-----\n"), cert_id]
  end

  # The not-found refusals carry an RFC 7807 problem document (RFC 8555
  # section 6.7) and are identical for missing and foreign-owned resources
  def expect_acme_not_found
    expect(last_response.status).to eq(404)
    expect(last_response.headers["Content-Type"]).to eq("application/problem+json")
    expect_unauthorized_problem_document

    [last_response.status, last_response.headers["Content-Type"], last_response.body]
  end

  def expect_unauthorized_problem_document
    parsed_body = JSON.parse(last_response.body)
    expect(parsed_body["type"]).to eq("urn:ietf:params:acme:error:unauthorized")
    expect(parsed_body["detail"]).to be_a(String)
  end

  context "when one account attacks another account's resources" do
    it "refuses order reads for another account's order" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)

      body = acme_request("/orders/#{order.id}", "", key: attacker_key, kid: attacker_kid)
      post_acme("/orders/#{order.id}", body)

      expect_acme_not_found
      expect(order.reload.status).to eq("pending")
    end

    it "refuses authorization reads for another account's order" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)
      authorization = order.authorizations.first

      body = acme_request("/authorizations/#{authorization.id}", "",
                          key: attacker_key, kid: attacker_kid)
      post_acme("/authorizations/#{authorization.id}", body)

      expect_acme_not_found
      expect(authorization.reload.status).to eq("pending")
    end

    it "refuses to trigger another account's challenge without side effects" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)
      challenge = order.authorizations.first.challenges.where(acme_type: "dns-01").first

      trigger_challenge(challenge, kid: attacker_kid, key: attacker_key)

      expect_acme_not_found

      # The validation attempt must never have run
      expect(challenge.reload.status).to eq("pending")
      expect(challenge.reload.validated).to be_nil
      expect(order.reload.status).to eq("pending")
    end

    it "refuses certificate downloads for another account's certificate" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)
      http_challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first
      trigger_challenge(http_challenge, kid: victim_kid, key: victim_key)
      cert, cert_id = issue_certificate(kid: victim_kid, key: victim_key,
                                        order:, domain: victim_domain)

      body = acme_request("/certificates/#{cert_id}", "",
                          key: attacker_key, kid: attacker_kid)
      post_acme("/certificates/#{cert_id}", body)

      # A foreign certificate answers exactly like a missing one: 422 with
      # no certificate material in the body
      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body)).to eq("error" => "Order not valid")
      expect(last_response.body).not_to include("BEGIN CERTIFICATE")

      record = Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)
      expect(record).not_to be_revoked
    end

    it "refuses to finalize another account's validated order" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)
      http_challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first
      trigger_challenge(http_challenge, kid: victim_kid, key: victim_key)
      order.reload
      expect(order.status).to eq("ready")

      # The attacker submits their own CSR against the victim's order
      cert_count = Bullion::Models::Certificate.count
      finalize_order(kid: attacker_kid, key: attacker_key, order:, domain: victim_domain)

      expect_acme_not_found

      # No certificate may be signed for the attacker's key
      order.reload
      expect(order.status).to eq("ready")
      expect(order.certificate_id).to be_nil
      expect(Bullion::Models::Certificate.count).to eq(cert_count)
    end

    it "refuses to revoke another account's certificate" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)
      http_challenge = order.authorizations.first.challenges.where(acme_type: "http-01").first
      trigger_challenge(http_challenge, kid: victim_kid, key: victim_key)
      cert, = issue_certificate(kid: victim_kid, key: victim_key,
                                order:, domain: victim_domain)

      body = acme_request("/revokecert",
                          { certificate: Base64.urlsafe_encode64(cert.to_der) },
                          key: attacker_key, kid: attacker_kid)
      post_acme("/revokecert", body)

      expect_acme_not_found

      record = Bullion::Models::Certificate.find_by(serial: cert.serial.to_i)
      expect(record).not_to be_revoked
      expect(record.revoked_at).to be_nil
      expect(record.revocation_reason).to be_nil
    end

    it "answers foreign and missing orders identically" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid: victim_kid, key: victim_key, domain: victim_domain)

      foreign = acme_request("/orders/#{order.id}", "", key: attacker_key, kid: attacker_kid)
      post_acme("/orders/#{order.id}", foreign)
      foreign_response = expect_acme_not_found

      missing = acme_request("/orders/999999", "", key: attacker_key, kid: attacker_kid)
      post_acme("/orders/999999", missing)
      missing_response = expect_acme_not_found

      # The refusal is indistinguishable: same status, headers, and body
      expect(foreign_response).to eq(missing_response)
    end
  end

  context "when an account uses its own resources" do
    it "lets the owner read their own order" do
      kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid:, key: victim_key, domain: victim_domain)

      body = acme_request("/orders/#{order.id}", "", key: victim_key, kid:)
      post_acme("/orders/#{order.id}", body)

      expect(last_response).to be_ok
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["identifiers"]).to eq([{ "type" => "dns", "value" => victim_domain }])
    end

    it "lets the owner read their own authorization" do
      kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid:, key: victim_key, domain: victim_domain)
      authorization = order.authorizations.first

      body = acme_request("/authorizations/#{authorization.id}", "",
                          key: victim_key, kid:)
      post_acme("/authorizations/#{authorization.id}", body)

      expect(last_response).to be_ok
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["identifier"]["value"]).to eq(victim_domain)
    end

    it "lets the owner read their own account" do
      kid = register_account(key: victim_key, email: victim_email)
      account_id = kid.split("/").last

      body = acme_request("/accounts/#{account_id}", "", key: victim_key, kid:)
      post_acme("/accounts/#{account_id}", body)

      expect(last_response).to be_ok
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("valid")
      expect(parsed_body["contact"]).to eq(["mailto:#{victim_email}"])
    end

    it "refuses account reads for another account" do
      attacker_kid = register_account(key: attacker_key, email: attacker_email)
      victim_kid = register_account(key: victim_key, email: victim_email)
      victim_id = victim_kid.split("/").last

      body = acme_request("/accounts/#{victim_id}", "",
                          key: attacker_key, kid: attacker_kid)
      post_acme("/accounts/#{victim_id}", body)

      expect(last_response.status).to eq(403)
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["error"]).to eq("Accounts can only view or update themselves")
    end

    it "lets the owner list their own orders" do
      kid = register_account(key: victim_key, email: victim_email)
      order = create_order(kid:, key: victim_key, domain: victim_domain)
      account_id = kid.split("/").last

      body = acme_request("/accounts/#{account_id}/orders", "", key: victim_key, kid:)
      post_acme("/accounts/#{account_id}/orders", body)

      expect(last_response).to be_ok
      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["orders"]).to include(match(%r{/orders/#{order.id}$}))
    end
  end
end
