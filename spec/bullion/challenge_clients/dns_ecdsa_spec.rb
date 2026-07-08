# frozen_string_literal: true

# Tests that ECDSA-backed accounts work correctly with the DNS challenge client.
# Issue #16 requested verifying ECDSA support via RSpec testing.
# The existing DNS challenge client spec only used RSA keys.
RSpec.describe Bullion::ChallengeClients::DNS do
  include BullionTest::Helpers

  subject do
    Bullion::RSpec::ChallengeClients::DNS.new(challenge)
  end

  before(:all) do
    @ec_key = OpenSSL::PKey::EC.generate("prime256v1")
    @ec_jwk = ecdsa_public_key_hash(@ec_key, "P-256")
    @ecdsa_account = Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["ecdsa.dns@example.com"],
      public_key: @ec_jwk
    )
  end

  let(:order) do
    @ecdsa_account.start_order(
      identifiers: [{ "type" => "dns", "value" => "ec-dns.test.domain" }]
    )
  end

  let(:authorization) do
    order.authorizations.first
  end

  let(:challenge) do
    authorization.challenges.where(acme_type: "dns-01").first
  end

  it "produces expected DNS record requests" do
    expected = "_acme-challenge.#{challenge.identifier}"
    expect(subject.dns_name).to eq(expected)
  end

  it "looks up records" do
    expect(subject.dns_value).to be_a(String)
  end

  it "generates proper digests using the ECDSA-derived thumbprint" do
    value_from_dns = subject.dns_value
    value_from_digest = subject.digest_value("#{challenge.token}.#{challenge.thumbprint}")
    expect(value_from_dns).to eq(value_from_digest)
  end

  it "performs attempts correctly" do
    expect(subject.attempt).to be(true)
  end
end
