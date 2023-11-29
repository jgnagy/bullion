# frozen_string_literal: true

RSpec.describe Bullion::Models::Account do
  include BullionTest::Helpers

  describe "with valid input" do
    describe "with RSA keys" do
      let(:account_key) { rsa_key }

      let(:public_key_hash) { rsa_public_key_hash(account_key) }

      let(:basic_account) do
        user_email = "john.doe@example.com"
        described_class.new(
          tos_agreed: true,
          contacts: [user_email],
          public_key: public_key_hash
        )
      end

      it("creates new accounts") { expect(basic_account.save).to be_truthy }

      it "allows starting new orders" do
        basic_account.save
        order = basic_account.start_order(identifiers: ["test.example.com"])
        expect(order.persisted?).to be(true)
      end
    end

    describe "with ECDSA keys" do
      let(:account_key) { ecdsa_key("P-521") }

      let(:public_key_hash) { ecdsa_public_key_hash(account_key, "P-521") }

      let(:basic_account) do
        user_email = "jane.doe@example.com"
        described_class.new(
          tos_agreed: true,
          contacts: [user_email],
          public_key: public_key_hash
        )
      end

      it("creates new accounts") { expect(basic_account.save).to be_truthy }

      it "allows starting new orders" do
        basic_account.save
        order = basic_account.start_order(identifiers: ["test.example.com"])
        expect(order.errors).to be_empty
      end
    end
  end
end
