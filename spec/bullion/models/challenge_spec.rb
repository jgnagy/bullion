# frozen_string_literal: true

RSpec.describe Bullion::Models::Challenge do
  subject do
    authorization.challenges.first
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
    @account.start_order(identifiers: [{ type: "dns", value: "some.crazy.test.domain" }])
  end

  let(:authorization) do
    order.authorizations.first
  end

  it "automatically sets tokens" do
    expect(subject.token).to be_a(String)
  end

  it "automatically sets expirations that are of type Time" do
    expect(subject.expires).to be_a(Time)
  end

  it "automatically sets expirations in the future" do
    expect(subject.expires).to be > Time.now
  end

  describe "#expired?" do
    it "is false while the challenge's lifetime remains" do
      subject.update!(expires: Time.now + 60)

      expect(subject).not_to be_expired
    end

    it "is true once the challenge's lifetime has elapsed" do
      subject.update!(expires: Time.now - 60)

      expect(subject).to be_expired
    end
  end

  it "provides a valid challenge client" do
    authorization.challenges.each do |challenge|
      expect(challenge.client).to be_a(Bullion::ChallengeClient)
    end
  end
end
