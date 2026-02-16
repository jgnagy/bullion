# frozen_string_literal: true

RSpec.describe Bullion::Models::Certificate do
  subject do
    cert = described_class.from_csr(csr)
    cert.data = csr.to_pem
    cert.requester = "testing123"
    cert
  end

  let(:key) do
    OpenSSL::PKey::RSA.new 2048
  end

  let(:csr) do
    csr = OpenSSL::X509::Request.new
    csr.subject = OpenSSL::X509::Name.new(
      [
        ["CN", "foo.example.com", OpenSSL::ASN1::UTF8STRING]
      ]
    )

    csr.public_key = key.public_key
    csr.sign(key, OpenSSL::Digest.new("SHA256"))
    csr
  end

  it "supports fingerprinting" do
    expect(subject.fingerprint).to be_a(String)
  end

  it "supports looking up the CN after creation" do
    expect(subject.cn).to eq("foo.example.com")
  end

  context "with Ed25519 keys" do
    let(:ed_key) do
      OpenSSL::PKey.generate_key("Ed25519")
    end

    let(:ed_csr) do
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.new([["CN", "ed25519.example.com"]])
      csr.public_key = ed_key
      csr.sign(ed_key, nil)
      csr
    end

    let(:ed_cert) do
      cert = described_class.from_csr(ed_csr)
      cert.data = ed_csr.to_pem
      cert.requester = "ed25519_test"
      cert
    end

    it "supports fingerprinting Ed25519 certificates" do
      expect(ed_cert.fingerprint).to be_a(String)
    end

    it "supports looking up the CN from Ed25519 certificates" do
      expect(ed_cert.cn).to eq("ed25519.example.com")
    end
  end
end
