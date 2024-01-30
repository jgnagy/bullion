# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Challenge model
    class Challenge < ActiveRecord::Base
      after_initialize :init_values, unless: :persisted?

      belongs_to :authorization

      validates :acme_type, inclusion: {
        in: -> { Bullion.config.acme.challenge_clients.map(&:acme_type) }
      }
      validates :status, inclusion: { in: %w[invalid pending processing valid] }

      def identifier
        authorization.identifier["value"]
      end

      def init_values
        self.expires ||= Time.now + (60 * 60)
        self.token ||= SecureRandom.alphanumeric(48)
      end

      def thumbprint
        cipher = OpenSSL::Digest.new("SHA256")
        digest = cipher.digest(lexicographically_ordered_public_key.to_json)
        Base64.urlsafe_encode64(digest).sub(/[\s=]*\z/, "")
      end

      def client
        challenge_class = Bullion.acme.challenge_clients.find { _1.acme_type == acme_type }

        unless challenge_class
          raise Bullion::Acme::Errors::UnsupportedChallengeType,
                "Challenge type '#{acme_type}' is not supported by Bullion."
        end

        challenge_class.new(self)
      end

      private

      def lexicographically_ordered_public_key
        jwk = authorization.order.account.public_key
        [["e", jwk["e"]], ["kty", jwk["kty"]], ["n", jwk["n"]]].to_h
      end
    end
  end
end
