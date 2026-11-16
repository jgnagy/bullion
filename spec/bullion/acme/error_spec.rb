# frozen_string_literal: true

# Every ACME error this gem can emit must either be a registered type in
# the IANA ACME Error Types registry (referenced by RFC 8555 section 6.7)
# or, for Bullion-specific conditions, a URI outside the ACME namespace.
RSpec.describe Bullion::Acme::Error do
  let(:registered_types) do
    %w[
      accountDoesNotExist alreadyRevoked badCSR badNonce badPublicKey
      badRevocationReason badSignatureAlgorithm caa compound connection dns
      externalAccountRequired incorrectResponse invalidContact malformed
      orderNotReady rateLimited rejectedIdentifier serverInternal tls
      unauthorized unsupportedContact unsupportedIdentifier userActionRequired
      autoRenewalCanceled autoRenewalExpired autoRenewalCancellationInvalid
      autoRenewalRevocationNotSupported unknownDelegation onionCAARequired
      alreadyReplaced
    ]
  end

  it "falls back to the registered serverInternal type" do
    expect(described_class.new.acme_error).to eq("urn:ietf:params:acme:error:serverInternal")
  end

  it "maps every concrete error to a registered type or the Bullion namespace" do
    described_class.subclasses.each do |klass|
      acme_error = klass.new.acme_error

      unless acme_error.start_with?("urn:ietf:params:acme:error:")
        expect(acme_error).to start_with("urn:ietf:params:bullion:error:"),
                              "#{klass} uses an unexpected namespace: #{acme_error}"
        next
      end

      type = acme_error.delete_prefix("urn:ietf:params:acme:error:")
      expect(registered_types).to include(type),
                                  "#{klass} uses unregistered type: #{acme_error}"
    end
  end
end
