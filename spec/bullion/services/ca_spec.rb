# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  def app
    described_class
  end

  before(:all) do
    @key = OpenSSL::PKey::RSA.new(2048)
    @stripped_key = @key.public_key
                        .to_pem
                        .gsub("-----BEGIN CERTIFICATE REQUEST-----\n", "")
                        .gsub("-----END CERTIFICATE REQUEST-----", "")
  end

  let(:public_key_hash) do
    {
      "e" => @key.params["e"].to_s,
      "kty" => "RSA",
      "n" => @stripped_key
    }
  end

  let(:account_email) { "john.doe@example.com" }

  let(:account) do
    Bullion::Models::Account.create(
      tos_agreed: true,
      contacts: [account_email],
      public_key: public_key_hash
    )
  end

  let(:identifiers) { ["a.test.domain", "other.test.domain"] }

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
    options "/accounts/#{account.id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /accounts/:id/orders" do
    options "/accounts/#{account.id}/orders"
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
    options "/orders/#{order.id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /orders/:id/finalize" do
    options "/orders/#{order.id}/finalize"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /authorizations/:id" do
    options "/authorizations/#{authorization.id}"
    expect(last_response).to be_ok
    expect(
      last_response.headers["Access-Control-Allow-Methods"].sort
    ).to eq(generic_req_methods)
  end

  it "provides reasonable OPTIONS for /challenges/:id" do
    options "/challenges/#{challenge.id}"
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

  xit "allows new client registrations" do
    expect(@acme_account.kid).to be_a(String)
    expect(URI(@acme_account.kid)).to be_a(URI)
    expect(URI(@acme_account.kid).path).to eq("/acme/accounts/1")
  end
end
