# frozen_string_literal: true

RSpec.describe Bullion::Models::Challenge do
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
    @account.start_order(identifiers: [{ type: "dns", value: "some.crazy.test.domain" }])
  end

  let(:authorization) do
    order.authorizations.first
  end

  subject do
    authorization.challenges.first
  end

  it "automatically sets tokens" do
    expect(subject.token).to be_a(String)
  end

  it "automatically sets expirations" do
    expect(subject.expires).to be_a(Time)
    expect(subject.expires).to be > Time.now
  end

  it "provides a valid challenge client" do
    authorization.challenges.each do |challenge|
      expect(challenge.client).to be_a(Bullion::ChallengeClient)
    end
  end
end
