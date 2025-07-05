# frozen_string_literal: true

module Bullion
  module ChallengeClients
    # ACME HTTP01 Challenge Client
    # @see https://tools.ietf.org/html/rfc8555#section-8.3
    class HTTP < ChallengeClient
      def self.acme_type = "http-01"
      def type = "HTTP01"

      def performs_challenge?
        response = begin
          retrieve_body(challenge_url)
        rescue SocketError
          LOGGER.debug "Failed to connect to #{challenge_url}"
          ""
        end

        token, thumbprint = response.split(".")
        token == challenge.token && thumbprint == challenge.thumbprint
      end

      def challenge_url
        "http://#{identifier}/.well-known/acme-challenge/#{challenge.token}"
      end

      def retrieve_body(url)
        HTTParty.get(
          url,
          verify: false,
          headers: { "User-Agent" => "Bullion/#{Bullion::VERSION}" }
        ).body
      end
    end
  end
end
