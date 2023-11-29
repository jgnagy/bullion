# frozen_string_literal: true

RSpec.describe Bullion::ChallengeClients::DNS do
  subject do
    # Wrapper around the real Challenge Client
    Bullion::RSpec::ChallengeClients::DNS.new(challenge)
  end

  before(:all) do
    @acme_client_key ||= OpenSSL::PKey::RSA.new(2048)
    stripped_key = @acme_client_key.public_key
                                   .to_pem
                                   .gsub("-----BEGIN CERTIFICATE REQUEST-----\n", "")
                                   .gsub("-----END CERTIFICATE REQUEST-----", "")
    key_hash = {
      "e" => @acme_client_key.params["e"].to_s,
      "kty" => "RSA",
      "n" => stripped_key
    }
    @account = Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["joe.blow@example.com"],
      public_key: key_hash
    )
    @account.save
  end

  let(:order) do
    @account.start_order(identifiers: [{ type: "dns", value: "one.test.domain" }])
  end

  let(:authorization) do
    order.authorizations.first
  end

  let(:challenge) do
    authorization.challenges.where(acme_type: "dns-01").first
  end

  it "produces expected DNS record requests" do
    expected_name = "_acme-challenge.#{challenge.identifier}"
    expect(subject.dns_name).to eq(expected_name)
  end

  it "looks up records" do
    expect(subject.dns_value).to be_a(String)
  end

  it "generates proper digests" do
    value_from_dns = subject.dns_value
    value_from_digest = subject.digest_value("#{challenge.token}.#{challenge.thumbprint}")
    expect(value_from_dns).to eq(value_from_digest)
  end

  it "performs attemps correctly" do
    expect(subject.attempt).to be(true)
  end
end
