# frozen_string_literal: true

RSpec.describe Bullion::Models::Authorization do
  include BullionTest::Helpers

  subject(:authorization) { order.authorizations.first }

  let(:account_key) { OpenSSL::PKey::RSA.new(2048) }

  let(:account) do
    Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["authorization_expiry@example.com"],
      public_key: rsa_public_key_hash(account_key)
    )
  end

  let(:order) do
    account.start_order(identifiers: [{ type: "dns", value: "expiry.test.domain" }])
  end

  describe "#expired?" do
    it "is false while the authorization's lifetime remains" do
      authorization.update!(expires: Time.now + 60)

      expect(authorization).not_to be_expired
    end

    it "is true once the authorization's lifetime has elapsed" do
      authorization.update!(expires: Time.now - 60)

      expect(authorization).to be_expired
    end
  end

  describe "#valid_for_issuance?" do
    it "is true for a valid, unexpired authorization" do
      authorization.update!(status: "valid", expires: Time.now + 60)

      expect(authorization.valid_for_issuance?).to be(true)
    end

    it "is false for an expired authorization even though its status is valid" do
      authorization.update!(status: "valid", expires: Time.now - 60)

      expect(authorization).to be_valid_status
      expect(authorization.valid_for_issuance?).to be(false)
    end

    it "is false for a pending, unexpired authorization" do
      authorization.update!(status: "pending", expires: Time.now + 60)

      expect(authorization.valid_for_issuance?).to be(false)
    end
  end
end
