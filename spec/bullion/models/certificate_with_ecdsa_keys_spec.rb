# frozen_string_literal: true

RSpec.describe Bullion::Models::Certificate do
  include BullionTest::Helpers

  context "with ECDSA P-256 keys" do
    let(:ec_key) { OpenSSL::PKey::EC.generate("prime256v1") }

    let(:ec_csr) do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new(
        [["CN", "ec.test.domain", OpenSSL::ASN1::UTF8STRING]]
      )
      csr.public_key = ec_key
      csr.sign(ec_key, OpenSSL::Digest.new("SHA256"))
      csr
    end

    let(:ec_cert) do
      cert = described_class.from_csr(ec_csr)
      cert.data = ec_csr.to_pem
      cert.requester = "ecdsa_test"
      cert
    end

    it "supports fingerprinting ECDSA certificates" do
      expect(ec_cert.fingerprint).to be_a(String)
    end

    it "supports looking up the CN from ECDSA certificates" do
      expect(ec_cert.cn).to eq("ec.test.domain")
    end

    it "stores the CSR fingerprint for ECDSA certificates" do
      expected_fp = Base64.encode64(
        OpenSSL::Digest::SHA1.digest(ec_csr.to_pem)
      ).chomp
      expect(ec_cert.csr_fingerprint).to eq(expected_fp)
    end

    it "assigns a serial number" do
      expect(ec_cert.serial).to be_a(Integer)
      expect(ec_cert.serial).to be_positive
    end
  end

  context "with ECDSA P-384 keys" do
    let(:ec_key) { OpenSSL::PKey::EC.generate("secp384r1") }

    let(:ec_csr) do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new(
        [["CN", "ec.test.domain", OpenSSL::ASN1::UTF8STRING]]
      )
      csr.public_key = ec_key
      csr.sign(ec_key, OpenSSL::Digest.new("SHA256"))
      csr
    end

    let(:ec_cert) do
      cert = described_class.from_csr(ec_csr)
      cert.data = ec_csr.to_pem
      cert.requester = "ecdsa_test"
      cert
    end

    it "supports fingerprinting P-384 certificates" do
      expect(ec_cert.fingerprint).to be_a(String)
    end

    it "supports looking up the CN from P-384 certificates" do
      expect(ec_cert.cn).to eq("ec.test.domain")
    end
  end

  context "with ECDSA P-521 keys" do
    let(:ec_key) { OpenSSL::PKey::EC.generate("secp521r1") }

    let(:ec_csr) do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new(
        [["CN", "ec.test.domain", OpenSSL::ASN1::UTF8STRING]]
      )
      csr.public_key = ec_key
      csr.sign(ec_key, OpenSSL::Digest.new("SHA256"))
      csr
    end

    let(:ec_cert) do
      cert = described_class.from_csr(ec_csr)
      cert.data = ec_csr.to_pem
      cert.requester = "ecdsa_test"
      cert
    end

    it "supports fingerprinting P-521 certificates" do
      expect(ec_cert.fingerprint).to be_a(String)
    end

    it "supports looking up the CN from P-521 certificates" do
      expect(ec_cert.cn).to eq("ec.test.domain")
    end
  end

  context "with invalid CSRs" do
    let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }

    it "handles CSR with no subject gracefully" do
      # Create a CSR without setting the subject
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      # Leave subject unset (defaults to empty/nil)
      csr.public_key = rsa_key
      csr.sign(rsa_key, OpenSSL::Digest.new("SHA256"))

      # from_csr should handle this gracefully - subject will be nil
      cert = described_class.from_csr(csr)
      expect(cert).to be_a(described_class)
      expect(cert.subject).to be_nil
    end

    it "handles CSR with empty subject string gracefully" do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      # Explicitly set an empty subject
      csr.subject = OpenSSL::X509::Name.new([])
      csr.public_key = rsa_key

      # Need to sign - but CSR with no CN, so we add SANs instead
      factory = OpenSSL::X509::ExtensionFactory.new
      cn_ext = factory.create_extension("subjectAltName", "DNS:test.test.domain")
      attr_set = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence([cn_ext])])
      csr.add_attribute(OpenSSL::X509::Attribute.new("extReq", attr_set))
      csr.sign(rsa_key, OpenSSL::Digest.new("SHA256"))

      # from_csr should handle this gracefully without crashing
      expect { described_class.from_csr(csr) }.not_to raise_error
      cert = described_class.from_csr(csr)
      expect(cert).to be_a(described_class)
    end
  end
end
