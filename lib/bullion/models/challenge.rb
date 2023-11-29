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
        cipher.hexdigest authorization.order.account.public_key.to_json
      end

      def client
        challenge_class = Bullion.acme.challenge_clients.find { _1.acme_type == acme_type }

        unless challenge_class
          raise Bullion::Acme::Errors::UnsupportedChallengeType,
                "Challenge type '#{acme_type}' is not supported by Bullion."
        end

        challenge_class.new(self)
      end
    end
  end
end
