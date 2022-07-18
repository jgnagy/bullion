# frozen_string_literal: true

module Bullion
  module ChallengeClients
    # ACME DNS01 Challenge Client
    # @see https://tools.ietf.org/html/rfc8555#section-8.4
    class DNS < ChallengeClient
      def type
        "DNS01"
      end

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

      def dns_value
        name = "_acme-challenge.#{identifier}"

        # Randomly select a nameserver to pull the TXT record
        nameserver = NAMESERVERS.sample

        LOGGER.debug "Looking up #{name}"
        records = records_for(name, nameserver)
        raise "Failed to find records for #{name}" unless records

        record = records.map(&:strings).flatten.first
        LOGGER.debug "Resolved #{name} to value #{record}"
        record
      rescue Resolv::ResolvError
        msg = ["Resolution error for #{name}"]
        msg << "via #{nameserver}" if nameserver
        LOGGER.info msg.join(" ")
        false
      rescue StandardError => e
        msg = ["Error '#{e.message}' for #{name}"]
        msg << "with #{nameserver}" if nameserver
        LOGGER.warn msg.join(" ")
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
