# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  before(:all) do
    @acme_client_key ||= OpenSSL::PKey::RSA.new(4096)
    @acme_client = Acme::Client.new(
      private_key: @acme_client_key,
      directory: "http://localhost:9292/acme/directory"
    )
    @acme_account = @acme_client.new_account(
      contact: "mailto:info@example.com",
      terms_of_service_agreed: true
    )
  end

  def app
    described_class
  end

  let(:expected_directory) do
    {
      meta: nil,
      new_nonce: URI("http://localhost:9292/acme/nonces"),
      new_account: URI("http://localhost:9292/acme/accounts"),
      new_order: URI("http://localhost:9292/acme/orders"),
      revoke_certificate: URI("http://localhost:9292/acme/revokecert"),
      key_change: URI("http://localhost:9292/acme/keychanges")
    }
  end

  it "provides the expected directory contents" do
    client_directory = @acme_client.instance_variable_get(:@directory)
    internal_directory = client_directory.instance_variable_get(:@directory)
    expect(internal_directory).to eq(expected_directory)
  end

  it "allows new client registrations" do
    expect(@acme_account.kid).to be_a(String)
    expect(URI(@acme_account.kid)).to be_a(URI)
    expect(URI(@acme_account.kid).path).to eq("/acme/accounts/1")
  end

  describe "valid requests" do
    it "allows new ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["foo.test.domain"])
      expect(acme_order).to be_a(Acme::Client::Resources::Order)
    end

    it "finds authorizations for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["bar.test.domain"])
      authorization = acme_order.authorizations.first
      expect(authorization).to be_a(Acme::Client::Resources::Authorization)
    end

    it "provides DNS01 challenges for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["baz.test.domain"])
      authorization = acme_order.authorizations.first
      challenge = authorization.dns
      expect(challenge).to be_a(Acme::Client::Resources::Challenges::DNS01)
      expect(challenge.record_name).to eq("_acme-challenge")
      expect(challenge.record_type).to eq("TXT")
      expect(challenge.record_content).to be_a(String)
    end

    it "provides HTTP01 challenges for ACME orders" do
      acme_order = @acme_client.new_order(identifiers: ["bin.test.domain"])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      expect(challenge).to be_a(Acme::Client::Resources::Challenges::HTTP01)
      expect(challenge.filename).to match(%r{^\.well-known/acme-challenge/.+})
      expect(challenge.content_type).to eq("text/plain")
      expect(challenge.file_content).to be_a(String)
    end

    it "executes DNS01 challenges for ACME orders" do
      domain = "blah.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.dns
      expect(challenge).to be_a(Acme::Client::Resources::Challenges::DNS01)
      challenge.request_validation
      challenge.reload
      expect(challenge.status).to eq("valid")
    end

    it "executes HTTP01 challenges for ACME orders" do
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      expect(challenge).to be_a(Acme::Client::Resources::Challenges::HTTP01)
      challenge.request_validation
      challenge.reload
      expect(challenge.status).to eq("valid")
    end

    it "finalizes ACME orders and allows downloading the signed cert" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: domain }
      )
      acme_order.finalize(csr:)
      expect(challenge.status).to eq("valid")
      acme_order.certificate
    end

    it "provides valid signed certificates" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "blammo.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: domain }
      )
      acme_order.finalize(csr:)
      expect(challenge.status).to eq("valid")
      cert = acme_order.certificate
      expect(cert).to start_with("-----BEGIN CERTIFICATE-----\n")
      decoded_cert = OpenSSL::X509::Certificate.new(cert)
      expect(decoded_cert.subject.to_s).to end_with("/CN=#{domain}")
      expect(decoded_cert.version).to eq(2) # Ensure x509v3 (version 2 in zero-indexed OpenSSL)
      extensions = decoded_cert.extensions.to_h { [it.oid, it.value] }
      expect(extensions["basicConstraints"]).to eq("CA:FALSE")
      expect(extensions["extendedKeyUsage"]).to eq("TLS Web Server Authentication")
      expect(extensions["subjectAltName"]).to eq("DNS:blammo.test.domain")
    end

    it "provides valid signed certificates for Ed25519 keys" do
      cert_key = OpenSSL::PKey.generate_key("Ed25519")
      domain = "ed25519.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: domain },
        digest: nil # Ed25519 doesn't use a separate digest
      )
      acme_order.finalize(csr:)
      expect(challenge.status).to eq("valid")
      cert = acme_order.certificate
      expect(cert).to start_with("-----BEGIN CERTIFICATE-----\n")
      decoded_cert = OpenSSL::X509::Certificate.new(cert)
      expect(decoded_cert.subject.to_s).to end_with("/CN=#{domain}")
      expect(decoded_cert.version).to eq(2)
      expect(decoded_cert.public_key.oid).to eq("ED25519")
      extensions = decoded_cert.extensions.to_h { [it.oid, it.value] }
      expect(extensions["basicConstraints"]).to eq("CA:FALSE")
      expect(extensions["extendedKeyUsage"]).to eq("TLS Web Server Authentication")
      expect(extensions["subjectAltName"]).to eq("DNS:ed25519.test.domain")
    end
  end

  describe "invalid requests" do
    it "rejects new empty ACME orders" do
      expect { @acme_client.new_order(identifiers: []) }.to(
        raise_error(Acme::Client::Error, "Empty order!")
      )
    end

    it "rejects new ACME orders for invalid domains" do
      domain = "foo.should.not.work"
      expect { @acme_client.new_order(identifiers: [domain]) }.to(
        raise_error(Acme::Client::Error, /"#{domain}"}\] not allowed/)
      )
    end

    it "fails to finalize ACME orders with invalid CSRs" do
      cert_key = OpenSSL::PKey::RSA.new(2048)
      domain = "boom.test.domain"
      acme_order = @acme_client.new_order(identifiers: [domain])
      authorization = acme_order.authorizations.first
      challenge = authorization.http
      challenge.request_validation
      challenge.reload
      csr = Acme::Client::CertificateRequest.new(
        private_key: cert_key,
        subject: { common_name: "boom.bad.bad" }
      )
      expect { acme_order.finalize(csr:) }.to(
        raise_error(Acme::Client::Error::BadCSR, "Bullion::Acme::Errors::BadCsr")
      )
    end
  end
end
