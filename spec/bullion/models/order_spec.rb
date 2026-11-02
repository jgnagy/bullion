# frozen_string_literal: true

RSpec.describe Bullion::Models::Order do
  include BullionTest::Helpers

  subject(:order) do
    account.start_order(identifiers: [{ type: "dns", value: "expiry.test.domain" }])
  end

  let(:account_key) { OpenSSL::PKey::RSA.new(2048) }

  let(:account) do
    Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["order_expiry@example.com"],
      public_key: rsa_public_key_hash(account_key)
    )
  end

  describe "#expired?" do
    it "is false while the order's lifetime remains" do
      order.update!(expires: Time.now + 60)

      expect(order).not_to be_expired
    end

    it "is true once the order's lifetime has elapsed" do
      order.update!(expires: Time.now - 60)

      expect(order).to be_expired
    end
  end

  describe "#ready_for_issuance?" do
    it "is false while the order is not ready" do
      order.authorizations.first.update!(status: "valid", expires: Time.now + 60)

      expect(order.ready_for_issuance?).to be(false)
    end

    it "is true when ready, unexpired, and every authorization is fresh" do
      order.authorizations.first.update!(status: "valid", expires: Time.now + 60)
      order.update!(status: "ready", expires: Time.now + 60)

      expect(order.ready_for_issuance?).to be(true)
    end

    it "is false when the order itself has expired" do
      order.authorizations.first.update!(status: "valid", expires: Time.now + 60)
      order.update!(status: "ready", expires: Time.now - 60)

      expect(order.ready_for_issuance?).to be(false)
    end

    it "is false when an authorization expires after the order became ready" do
      authorization = order.authorizations.first
      authorization.update!(status: "valid", expires: Time.now - 60)
      order.update!(status: "ready", expires: Time.now + 60)

      expect(order.ready_for_issuance?).to be(false)
    end
  end
end
