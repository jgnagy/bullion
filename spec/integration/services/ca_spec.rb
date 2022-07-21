# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  before(:all) do
    @acme_client_key ||= OpenSSL::PKey::RSA.new(4096)
    @acme_client = Acme::Client.new(
      private_key: @acme_client_key,
      directory: "http://localhost:9292/acme/directory"
    )
    @acme_account = @acme_client.new_account(
      contact: "mailto:info@example.com",
      terms_of_service_agreed: true
    )
  end

  def app
    described_class
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

  let(:directory_req_methods) do
    %w[GET]
  end

  let(:nonce_req_methods) do
    %w[GET HEAD].sort
  end

  let(:generic_req_methods) do
    %w[POST]
  end

  it "provides reasonable OPTIONS for /directory" do
    options "/directory"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(directory_req_methods)
  end

  it "provides reasonable OPTIONS for /nonces" do
    options "/nonces"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(nonce_req_methods)
  end

  it "provides reasonable OPTIONS for /accounts" do
    options "/accounts"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /accounts/:id" do
    account_id = @acme_account.url.split("/").last
    options "/accounts/#{account_id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /accounts/:id/orders" do
    account_id = @acme_account.url.split("/").last
    options "/accounts/#{account_id}/orders"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /orders" do
    options "/orders"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /orders/:id" do
    order = @acme_client.new_order(identifiers: ["bar.test.domain"])
    order_id = order.url.split("/").last
    options "/orders/#{order_id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /orders/:id/finalize" do
    order = @acme_client.new_order(identifiers: ["bar.test.domain"])
    order_id = order.url.split("/").last
    options "/orders/#{order_id}/finalize"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /authorizations/:id" do
    order = @acme_client.new_order(identifiers: ["bar.test.domain"])
    authz = order.authorizations.first
    authz_id = authz.url.split("/").last
    options "/authorizations/#{authz_id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /challenges/:id" do
    order = @acme_client.new_order(identifiers: ["bar.test.domain"])
    authz = order.authorizations.first
    chall = authz.challenges.last
    chall_id = chall.url.split("/").last
    options "/challenges/#{chall_id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /cabundle" do
    options "/cabundle"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(directory_req_methods)
  end

  it "allows access to the CA directory" do
    get "/directory"

    expect(last_response).to be_ok # 200 OK
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

    expect(last_response.status).to be(204) # no content
    expect(last_response.headers).to include("Replay-Nonce")
    expect(last_response.headers["Replay-Nonce"]).to be_a(String)
    expect(last_response.headers["Link"]).to eq('<http://example.org/directory>;rel="index"')
    expect(last_response.headers["Cache-Control"]).to eq("no-store")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "provides usable nonces via HEAD requests" do
    head "/nonces"

    expect(last_response.status).to be(200) # no content
    expect(last_response.headers).to include("Replay-Nonce")
    expect(last_response.headers["Replay-Nonce"]).to be_a(String)
    expect(last_response.headers["Link"]).to eq('<http://example.org/directory>;rel="index"')
    expect(last_response.headers["Cache-Control"]).to eq("no-store")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "allows new client registrations" do
    expect(@acme_account.kid).to be_a(String)
    expect(URI(@acme_account.kid)).to be_a(URI)
    expect(URI(@acme_account.kid).path).to eq("/acme/accounts/1")
  end

  describe "valid requests" do
    it "allows new ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["foo.test.domain"])
      expect(acme_order).to be_a(::Acme::Client::Resources::Order)
    end

    it "finds authorizations for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["bar.test.domain"])
      authorization = acme_order.authorizations.first
      expect(authorization).to be_a(::Acme::Client::Resources::Authorization)
    end

    it "provides DNS01 challenges for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["baz.test.domain"])
      authorization = acme_order.authorizations.first
      challenge = authorization.dns
      expect(challenge).to be_a(::Acme::Client::Resources::Challenges::DNS01)
      expect(challenge.record_name).to eq("_acme-challenge")
      expect(challenge.record_type).to eq("TXT")
      expect(challenge.record_content).to be_a(String)
    end

    it "provides HTTP01 challenges for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["bin.test.domain"])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      expect(challenge).to be_a(::Acme::Client::Resources::Challenges::HTTP01)
      expect(challenge.filename).to match(%r{^\.well-known/acme-challenge/.+})
      expect(challenge.content_type).to eq("text/plain")
      expect(challenge.file_content).to be_a(String)
    end

    it "executes DNS01 challenges for ACME orders" do
      domain = "blah.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.dns
      expect(challenge).to be_a(::Acme::Client::Resources::Challenges::DNS01)
      challenge.request_validation
      challenge.reload
      expect(challenge.status).to eq("valid")
    end

    it "executes HTTP01 challenges for ACME orders" do
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      expect(challenge).to be_a(::Acme::Client::Resources::Challenges::HTTP01)
      challenge.request_validation
      challenge.reload
      expect(challenge.status).to eq("valid")
    end

    it "finalizes ACME orders and allows downloading the signed cert" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: domain }
      )
      acme_order.finalize(csr:)
      expect(challenge.status).to eq("valid")
      acme_order.certificate
    end

    it "provides valid signed certificates" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "blammo.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: domain }
      )
      acme_order.finalize(csr:)
      expect(challenge.status).to eq("valid")
      cert = acme_order.certificate
      expect(cert).to start_with("-----BEGIN CERTIFICATE-----\n")
      decoded_cert = OpenSSL::X509::Certificate.new(cert)
      expect(decoded_cert.subject.to_s).to end_with("/CN=#{domain}")
      extensions = decoded_cert.extensions.to_h { |ext| [ext.oid, ext.value] }
      expect(extensions["basicConstraints"]).to eq("CA:FALSE")
      expect(extensions["extendedKeyUsage"]).to eq("TLS Web Server Authentication")
      expect(extensions["subjectAltName"]).to eq("DNS:blammo.test.domain")
    end
  end

  describe "invalid requests" do
    it "rejects new empty ACME orders" do
      expect { @acme_client.new_order(identifiers: []) }.to(
        raise_error(Acme::Client::Error, "Empty order!")
      )
    end

    it "rejects new ACME orders for invalid domains" do
      domain = "foo.should.not.work"
      expect { @acme_client.new_order(identifiers: [domain]) }.to(
        raise_error(
          Acme::Client::Error,
          %(Domains [{"type"=>"dns", "value"=>"#{domain}"}] not allowed)
        )
      )
    end

    it "fails to finalize ACME orders with invalid CSRs" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: "boom.bad.bad" }
      )
      expect { acme_order.finalize(csr:) }.to(
        raise_error(Acme::Client::Error::BadCSR, "Bullion::Acme::Errors::BadCsr")
      )
    end
  end
end
