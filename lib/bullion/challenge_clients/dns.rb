# frozen_string_literal: true

module Bullion
  module ChallengeClients
    # ACME DNS01 Challenge Client
    # @see https://tools.ietf.org/html/rfc8555#section-8.4
    class DNS < ChallengeClient
      def self.acme_type = "dns-01"
      def type = "DNS01"

      def perform
        value = dns_value
        expected_value = digest_value("#{challenge.token}.#{challenge.thumbprint}")

        value == expected_value
      end

      def digest_value(string)
        digester = OpenSSL::Digest.new("SHA256")
        digest   = digester.digest(string)
        # clean up the digest output so it can match the provided challenge value
        Base64.urlsafe_encode64(digest).sub(/[\s=]*\z/, "")
      end

      def dns_name
        "_acme-challenge.#{identifier}"
      end

      def dns_value
        # Randomly select a nameserver to pull the TXT record
        nameserver = Bullion.config.nameservers.sample

        LOGGER.debug "Looking up #{dns_name}"
        records = records_for(dns_name, nameserver)
        raise "Failed to find records for #{dns_name}" unless records

        record = records.map(&:strings).flatten.first
        LOGGER.debug "Resolved #{dns_name} to value #{record}"
        record
      rescue StandardError => e
        msg = ["Resolution error '#{e.message}' for #{dns_name}"]
        msg << "via #{nameserver}" if nameserver
        LOGGER.info msg.join(" ")
        false
      end

      def records_for(name, nameserver = nil)
        if nameserver
          Resolv::DNS.open(nameserver:) do |dns|
            dns.getresources(name, Resolv::DNS::Resource::IN::TXT)
          end
        else
          Resolv::DNS.open do |dns|
            dns.getresources(name, Resolv::DNS::Resource::IN::TXT)
          end
        end
      end
    end
  end
end
