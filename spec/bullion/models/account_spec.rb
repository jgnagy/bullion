# frozen_string_literal: true

RSpec.describe Bullion::Models::Account do
  describe "with valid input" do
    describe "with RSA keys" do
      let(:public_key_hash) do
        key = OpenSSL::PKey::RSA.new(2048)
        stripped_key = key.public_key
                          .to_pem
                          .gsub("-----BEGIN CERTIFICATE REQUEST-----\n", "")
                          .gsub("-----END CERTIFICATE REQUEST-----", "")
        {
          "e" => key.params["e"].to_s,
          "kty" => "RSA",
          "n" => stripped_key
        }
      end

      let(:basic_account) do
        user_email = "john.doe@example.com"
        described_class.new(
          tos_agreed: true,
          contacts: [user_email],
          public_key: public_key_hash
        )
      end

      it "creates new accounts" do
        expect(basic_account.valid?).to be(true)
        expect(basic_account.save).to be_truthy
      end

      it "allows starting new orders" do
        basic_account.save
        order = basic_account.start_order(identifiers: ["test.example.com"])
        expect(order.valid?).to be(true)
        expect(order.errors).to be_empty
      end
    end

    describe "with ECDSA keys" do
      let(:public_key_hash) do
        key = OpenSSL::PKey::EC.new("secp384r1")
        key.generate_key
        hex_key = key.public_key.to_bn.to_s(16)
        hex_length = hex_key.size
        hex_x = hex_key[2, (hex_length / 2)]
        hex_y = hex_key[(2 + (hex_length / 2)), (hex_length / 2)]
        x = Base64.urlsafe_encode64(
          OpenSSL::BN.new([hex_x].pack("H*"), 2).to_s(2)
        ).sub(/[\s=]*$/, "")
        y = Base64.urlsafe_encode64(
          OpenSSL::BN.new([hex_y].pack("H*"), 2).to_s(2)
        ).sub(/[\s=]*$/, "")
        {
          "x" => x,
          "y" => y,
          "crv" => "P-256"
        }
      end

      let(:basic_account) do
        user_email = "jane.doe@example.com"
        described_class.new(
          tos_agreed: true,
          contacts: [user_email],
          public_key: public_key_hash
        )
      end

      it "creates new accounts" do
        expect(basic_account.valid?).to be(true)
        expect(basic_account.save).to be_truthy
      end

      it "allows starting new orders" do
        basic_account.save
        order = basic_account.start_order(identifiers: ["test.example.com"])
        expect(order.valid?).to be(true)
        expect(order.errors).to be_empty
      end
    end
  end
end
