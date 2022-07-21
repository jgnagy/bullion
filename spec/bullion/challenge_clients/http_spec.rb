# frozen_string_literal: true

RSpec.describe Bullion::ChallengeClients::DNS do
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
      contacts: ["someone.else@example.com"],
      public_key: key_hash
    )
    @account.save
  end

  let(:order) do
    @account.start_order(identifiers: [{ type: "dns", value: "two.test.domain" }])
  end

  let(:authorization) do
    order.authorizations.first
  end

  let(:challenge) do
    authorization.challenges.http01.first
  end

  subject do
    # Wrapper around the real Challenge Client
    Bullion::RSpec::ChallengeClients::HTTP.new(challenge)
  end

  it "produces expected URLs" do
    expected_url = "http://#{challenge.identifier}/.well-known/acme-challenge/#{challenge.token}"
    expect(subject.challenge_url).to be_a(String)
    expect(subject.challenge_url).to eq(expected_url)
  end

  it "performs attempts correctly" do
    expect(subject.attempt).to be(true)
  end
end
