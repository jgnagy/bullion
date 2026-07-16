# frozen_string_literal: true

RSpec.describe Bullion::Models::Certificate do
  include BullionTest::Helpers

  context "with a newly created certificate" do
    let(:rsa_key) { OpenSSL::PKey::RSA.new(2_048) }
    let(:rsa_csr) do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new([["CN", "test.domain", OpenSSL::ASN1::UTF8STRING]])
      csr.public_key = rsa_key
      csr.sign(rsa_key, OpenSSL::Digest.new("SHA256"))
      csr
    end

    let(:cert) do
      c = described_class.from_csr(rsa_csr)
      c.data = rsa_csr.to_pem
      c.requester = "test_user"
      c
    end

    it "is not revoked by default" do
      expect(cert.revoked?).to be false
    end

    it "returns true when the revoked attribute is set to true" do
      cert.revoked = true
      expect(cert.revoked?).to be true
    end
  end
end
