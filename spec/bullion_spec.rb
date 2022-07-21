# frozen_string_literal: true

RSpec.describe Bullion do
  it "has a version number" do
    expect(Bullion::VERSION).not_to be nil
  end

  it "provides access to the CA's private key" do
    expect(Bullion.ca_key).to be_an(OpenSSL::PKey::RSA)
  end

  it "provides access to the CA's public key" do
    expect(Bullion.ca_cert).to be_an(OpenSSL::X509::Certificate)
  end

  it "validates its configuration" do
    expect { Bullion.validate_config! }.not_to raise_exception
  end

  it "supports re-reading keys from the filesystem" do
    expect(Bullion.rotate_keys!).to be(true)
  end
end
