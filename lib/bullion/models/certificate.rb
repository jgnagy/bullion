# frozen_string_literal: true

module Bullion
  module Models
    # SSL Certificate model
    class Certificate < ActiveRecord::Base
      serialize :alternate_names, coder: JSON

      after_initialize :init_values, unless: :persisted?

      validates_presence_of :subject

      def init_values
        self.serial ||= SecureRandom.hex(4).to_i(16)
      end

      def fingerprint
        Base64.encode64(OpenSSL::Digest::SHA1.digest(data))
      end

      def cn
        subject.split("/").grep(/^CN=/).first.split("=").last
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
