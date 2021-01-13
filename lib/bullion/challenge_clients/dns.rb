# frozen_string_literal: true

module Bullion
  module ChallengeClients
    # ACME DNS01 Challenge Client
    # @see https://tools.ietf.org/html/rfc8555#section-8.4
    class DNS < ChallengeClient
      def type
        'DNS01'
      end

      def perform
        value = dns_value

        digester = OpenSSL::Digest.new('SHA256')
        digest   = digester.digest "#{challenge.token}.#{challenge.thumbprint}"
        # clean up the digest output so it can match the provided challenge value
        expected_value = Base64.urlsafe_encode64(digest).sub(/[\s=]*\z/, '')

        value == expected_value
      end

      def dns_value
        name = "_acme-challenge.#{identifier}"

        # Randomly select a nameserver to pull the TXT record
        nameserver = NAMESERVERS.sample

        begin
          records = Resolv::DNS.open(nameserver: nameserver) do |dns|
            dns.getresources(
              name,
              Resolv::DNS::Resource::IN::TXT
            )
          end
          record = records.map(&:strings).flatten.first
          LOGGER.debug "Resolved #{name} to value #{record}"
          record
        rescue Resolv::ResolvError
          LOGGER.info "Resolution error for #{name} via #{nameserver}"
          false
        rescue StandardError => e
          LOGGER.warn "Error '#{e.message}' for #{name} with #{nameserver}"
          false
        end
      end
    end
  end
end
