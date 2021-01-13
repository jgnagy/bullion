# frozen_string_literal: true

RSpec.describe Bullion::Models::Certificate do
  let(:key) do
    OpenSSL::PKey::RSA.new 2048
  end

  let(:csr) do
    csr = OpenSSL::X509::Request.new
    csr.version = 2
    csr.subject = OpenSSL::X509::Name.new(
      [
        ['CN', 'foo.example.com', OpenSSL::ASN1::UTF8STRING]
      ]
    )

    csr.public_key = key.public_key
    csr.sign(key, OpenSSL::Digest::SHA256.new)
    csr
  end

  subject do
    cert = Bullion::Models::Certificate.from_csr(csr)
    cert.data = csr.to_pem
    cert.requester = 'testing123'
    cert
  end

  it 'supports fingerprinting' do
    expect(subject.fingerprint).to be_a(String)
  end

  it 'supports looking up the CN after creation' do
    expect(subject.cn).to eq('foo.example.com')
  end
end
