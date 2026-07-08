# frozen_string_literal: true

# Tests that ECDSA-backed accounts work correctly with the HTTP challenge client.
# Issue #16 requested verifying ECDSA support via RSpec testing.
# The existing HTTP challenge client spec only used RSA keys.
RSpec.describe Bullion::ChallengeClients::HTTP do
  include BullionTest::Helpers

  subject do
    Bullion::RSpec::ChallengeClients::HTTP.new(challenge)
  end

  before(:all) do
    @ec_key = OpenSSL::PKey::EC.generate("prime256v1")
    @ec_jwk = ecdsa_public_key_hash(@ec_key, "P-256")
    @ecdsa_account = Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["ecdsa.http@example.com"],
      public_key: @ec_jwk
    )
  end

  let(:order) do
    @ecdsa_account.start_order(
      identifiers: [{ "type" => "dns", "value" => "ec-http.test.domain" }]
    )
  end

  let(:authorization) do
    order.authorizations.first
  end

  let(:challenge) do
    authorization.challenges.where(acme_type: "http-01").first
  end

  it "produces expected URLs" do
    expected = "http://#{challenge.identifier}/.well-known/acme-challenge/#{challenge.token}"
    expect(subject.challenge_url).to eq(expected)
  end

  it "performs attempts correctly" do
    expect(subject.attempt).to be(true)
  end

  it "uses the correct thumbprint derived from the ECDSA public key" do
    # The RSpec HTTP client returns "#{token}.#{thumbprint}"
    # Verify the thumbprint matches the challenge's computed thumbprint
    response_body = subject.retrieve_body(subject.challenge_url)
    _token, thumbprint = response_body.split(".")
    expect(thumbprint).to eq(challenge.thumbprint)
  end
end
