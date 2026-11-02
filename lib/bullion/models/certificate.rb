# frozen_string_literal: true

module Bullion
  module Models
    # SSL Certificate model
    class Certificate < ActiveRecord::Base
      serialize :alternate_names, coder: JSON

      after_initialize :init_values, unless: :persisted?

      validates_presence_of :subject

      has_one :order

      def init_values
        # CABF Baseline Requirements require at least 64 bits of CSPRNG output
        # in certificate serial numbers. Eight random bytes provide that, but
        # the serial column is a signed BIGINT, so clear the top bit to keep
        # the value positive and storable. Existing certificates keep their
        # serials; this only affects new issuances.
        self.serial ||= SecureRandom.hex(8).to_i(16) & 0x7FFF_FFFF_FFFF_FFFF
      end

      def fingerprint
        Base64.encode64(OpenSSL::Digest::SHA1.digest(data))
      end

      def cn
        subject.split("/").grep(/^CN=/).first.split("=").last
      end

      # Returns true if the certificate has been revoked
      def revoked?
        revoked == true
      end

      def self.from_csr(csr)
        subjt = csr.subject if csr.subject && !csr.subject.to_s.empty?

        cert = new(
          csr_fingerprint: Base64.encode64(OpenSSL::Digest::SHA1.digest(csr.to_pem)).chomp
        )

        cert.subject = subjt if subjt
        cert
      end
    end
  end
end
