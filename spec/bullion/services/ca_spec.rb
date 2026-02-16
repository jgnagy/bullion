# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  include BullionTest::Helpers

  def app
    described_class
  end

  let(:account_key) { rsa_key }

  let(:account_email) { "john.doe@example.com" }

  let(:account) do
    Bullion::Models::Account.create(
      tos_agreed: true,
      contacts: [account_email],
      public_key: rsa_public_key_hash(account_key)
    )
  end

  let(:identifiers) do
    [
      { "type" => "dns", "value" => "a.test.domain" },
      { "type" => "dns", "value" => "other.test.domain" }
    ]
  end

  let(:order) do
    Bullion::Models::Order.create!(
      not_after: Time.now + (90 * 24 * 60 * 60),
      status: "pending",
      identifiers:,
      account:
    )
  end

  let(:authorization) do
    Bullion::Models::Authorization.create!(
      identifier: identifiers.last,
      order:
    )
  end

  let(:challenge) do
    Bullion::Models::Challenge.create!(
      acme_type: "http-01",
      authorization:
    )
  end

  let(:directory_response_body) do
    {
      "caBundle" => "http://example.org/cabundle",
      "keyChange" => "http://example.org/keychanges",
      "newAccount" => "http://example.org/accounts",
      "newNonce" => "http://example.org/nonces",
      "newOrder" => "http://example.org/orders",
      "revokeCert" => "http://example.org/revokecert"
    }
  end

  let(:directory_req_methods) { %w[GET] }

  let(:nonce_req_methods) { %w[GET HEAD].sort }

  let(:generic_req_methods) { %w[POST] }

  it "returns 200 OK for OPTIONS requests for /directory" do
    options "/directory"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /directory" do
    options "/directory"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(directory_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /nonces" do
    options "/nonces"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /nonces" do
    options "/nonces"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(nonce_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /accounts" do
    options "/accounts"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /accounts" do
    options "/accounts"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /accounts/:id" do
    options "/accounts/#{account.id}"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /accounts/:id" do
    options "/accounts/#{account.id}"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /accounts/:id/orders" do
    options "/accounts/#{account.id}/orders"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /accounts/:id/orders" do
    options "/accounts/#{account.id}/orders"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /orders" do
    options "/orders"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /orders" do
    options "/orders"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /orders/:id" do
    options "/orders/#{order.id}"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /orders/:id" do
    options "/orders/#{order.id}"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /orders/:id/finalize" do
    options "/orders/#{order.id}/finalize"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /orders/:id/finalize" do
    options "/orders/#{order.id}/finalize"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /authorizations/:id" do
    options "/authorizations/#{authorization.id}"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /authorizations/:id" do
    options "/authorizations/#{authorization.id}"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /challenges/:id" do
    options "/challenges/#{challenge.id}"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /challenges/:id" do
    options "/challenges/#{challenge.id}"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "returns 200 OK for OPTIONS requests for /cabundle" do
    options "/cabundle"
    expect(last_response).to be_ok
  end

  it "provides reasonable OPTIONS for /cabundle" do
    options "/cabundle"
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(directory_req_methods)
  end

  it "returns 200 OK for GET requests for /directory" do
    get "/directory"
    expect(last_response).to be_ok
  end

  it "allows access to the CA directory" do
    get "/directory"

    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(JSON.parse(last_response.body)).to eq(directory_response_body)
  end

  it "provides access to the CA's public key bundle" do
    get "/cabundle"

    expect(last_response).to be_ok # 200 OK
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(last_response.body).to eq(
      File.read(File.join(File.expand_path("."), "tmp", "tls.crt"))
    )
  end

  it "provides usable nonces" do
    get "/nonces"

    expect(last_response).to be_no_content # no content
    expect(last_response.headers).to include("Replay-Nonce")
    expect(last_response.headers["Replay-Nonce"]).to be_a(String)
    expect(last_response.headers["Link"]).to eq('<http://example.org/directory>;rel="index"')
    expect(last_response.headers["Cache-Control"]).to eq("no-store")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "provides usable nonces via HEAD requests" do
    head "/nonces"

    expect(last_response).to be_ok # no content
    expect(last_response.headers).to include("Replay-Nonce")
    expect(last_response.headers["Replay-Nonce"]).to be_a(String)
    expect(last_response.headers["Link"]).to eq('<http://example.org/directory>;rel="index"')
    expect(last_response.headers["Cache-Control"]).to eq("no-store")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  context "with RSA keys" do
    it "allows new client registrations" do
      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key)
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: ["mailto:#{account_email}"]
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      # p last_response.body

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/accounts/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("valid")
      expect(parsed_body["contact"]).to eq(["mailto:#{account_email}"])
      expect(parsed_body["orders"]).to match(%r{^http://.+/accounts/[0-9]+/orders$})
    end

    it "validates existing client registrations" do
      account # need to create the account to use it

      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key)
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: ["mailto:#{account_email}"],
        onlyReturnExisting: true
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/accounts/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("valid")
      expect(parsed_body["contact"]).to eq(["mailto:#{account_email}"])
      expect(parsed_body["orders"]).to match(%r{http://.+/accounts/[0-9]+/orders})
    end

    it "validates acme account fields" do
      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key)
      }.to_json
      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: [account_email]
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_bad_request
      expect(last_response.headers["Content-Type"]).to eq("application/problem+json")
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to eq("urn:ietf:params:acme:error:unsupportedContact")
      expect(parsed_body["detail"]).to eq("Bullion::Acme::Errors::UnsupportedContact")
    end

    it "allows submitting new orders" do
      account # need to create the account to use it

      get "/nonces"

      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "RS256",
        jwk: rsa_public_key_hash(account_key),
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
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/orders/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("pending")
      expect(parsed_body).to include("expires")
      expect(parsed_body).to include("notBefore")
      expect(parsed_body).to include("notAfter")
      expect(parsed_body).to include("authorizations")
      expect(parsed_body["authorizations"]).to be_an(Array)
      expect(parsed_body["authorizations"].size).to eq(2)
      expect(parsed_body["identifiers"]).to eq(identifiers)
      expect(parsed_body["finalize"]).to match(%r{http://.+/orders/[0-9]+/finalize})
    end
  end

  context "with ECDSA keys" do
    it "allows new client registrations" do
      account_key = ecdsa_key

      jwk = {
        typ: "JWT",
        alg: "ES256",
        jwk: ecdsa_public_key_hash(account_key)
      }.to_json

      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: ["mailto:#{account_email}"]
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/accounts/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("valid")
      expect(parsed_body["contact"]).to eq(["mailto:#{account_email}"])
      expect(parsed_body["orders"]).to match(%r{^http://.+/accounts/[0-9]+/orders$})
    end

    it "allows submitting new orders" do
      account_key = ecdsa_key

      # Create an account so we can use it
      Bullion::Models::Account.create(
        tos_agreed: true,
        contacts: [account_email],
        public_key: ecdsa_public_key_hash(account_key)
      )

      get "/nonces"

      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "ES256",
        jwk: ecdsa_public_key_hash(account_key),
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
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/orders/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("pending")
      expect(parsed_body).to include("expires")
      expect(parsed_body).to include("notBefore")
      expect(parsed_body).to include("notAfter")
      expect(parsed_body).to include("authorizations")
      expect(parsed_body["authorizations"]).to be_an(Array)
      expect(parsed_body["authorizations"].size).to eq(2)
      expect(parsed_body["identifiers"]).to eq(identifiers)
      expect(parsed_body["finalize"]).to match(%r{http://.+/orders/[0-9]+/finalize})
    end
  end

  context "with EdDSA keys" do
    it "allows new client registrations" do
      account_key = eddsa_key

      jwk = {
        typ: "JWT",
        alg: "EdDSA",
        jwk: eddsa_public_key_hash(account_key)
      }.to_json

      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: ["mailto:#{account_email}"]
      }.to_json
      encoded_payload = acme_base64(payload)
      signature_data = "#{encoded_jwk}.#{encoded_payload}"

      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/accounts/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("valid")
      expect(parsed_body["contact"]).to eq(["mailto:#{account_email}"])
      expect(parsed_body["orders"]).to match(%r{^http://.+/accounts/[0-9]+/orders$})
    end

    it "allows submitting new orders" do
      account_key = eddsa_key

      # Create an account so we can use it
      Bullion::Models::Account.create(
        tos_agreed: true,
        contacts: [account_email],
        public_key: eddsa_public_key_hash(account_key)
      )

      get "/nonces"

      nonce = last_response.headers["Replay-Nonce"]

      jwk = {
        typ: "JWT",
        alg: "EdDSA",
        jwk: eddsa_public_key_hash(account_key),
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
        signature: acme_sign(account_key, signature_data)
      }.to_json

      post "/orders", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response).to be_created
      expect(last_response.headers["Content-Type"]).to eq("application/json")
      expect(last_response.headers["Location"]).to match(%r{^http://.+/orders/[0-9]+$})
      expect(last_response.body).to be_a(String)

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["status"]).to eq("pending")
      expect(parsed_body).to include("expires")
      expect(parsed_body).to include("notBefore")
      expect(parsed_body).to include("notAfter")
      expect(parsed_body).to include("authorizations")
      expect(parsed_body["authorizations"]).to be_an(Array)
      expect(parsed_body["authorizations"].size).to eq(2)
      expect(parsed_body["identifiers"]).to eq(identifiers)
      expect(parsed_body["finalize"]).to match(%r{http://.+/orders/[0-9]+/finalize})
    end

    it "rejects Ed448 with badPublicKey error" do
      # Create a mock Ed448 public key hash (Ed448 has 57-byte public keys)
      ed448_jwk = {
        kty: "OKP",
        crv: "Ed448",
        x: Base64.urlsafe_encode64("a" * 57, padding: false)
      }

      jwk = {
        typ: "JWT",
        alg: "EdDSA",
        jwk: ed448_jwk
      }.to_json

      encoded_jwk = acme_base64(jwk)
      payload = {
        contact: ["mailto:#{account_email}"]
      }.to_json
      encoded_payload = acme_base64(payload)

      # We can't actually sign with Ed448, but we'll send a dummy signature
      # The error should occur during key parsing, before signature verification
      body = {
        protected: encoded_jwk,
        payload: encoded_payload,
        signature: acme_base64("dummy_signature")
      }.to_json

      post "/accounts", body, { "CONTENT_TYPE" => "application/jose+json" }

      expect(last_response.status).to eq(400)
      expect(last_response.headers["Content-Type"]).to eq("application/problem+json")

      parsed_body = JSON.parse(last_response.body)
      expect(parsed_body["type"]).to eq("urn:ietf:params:acme:error:badPublicKey")
      expect(parsed_body["detail"]).to include("Ed448")
      expect(parsed_body["detail"]).to include("Ed25519")
    end
  end
end
