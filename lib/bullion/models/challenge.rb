# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Challenge model
    class Challenge < ActiveRecord::Base
      after_initialize :init_values, unless: :persisted?

      belongs_to :authorization

      validates :acme_type, inclusion: { in: %w[http-01 dns-01] }
      validates :status, inclusion: { in: %w[invalid pending processing valid] }

      def init_values
        self.expires ||= Time.now + (60 * 60)
        self.token ||= SecureRandom.alphanumeric(48)
      end

      def thumbprint
        cipher = OpenSSL::Digest.new('SHA256')
        cipher.hexdigest authorization.order.account.public_key.to_json
      end

      def client
        case acme_type
        when 'dns-01'
          ChallengeClients::DNS.new(self)
        when 'http-01'
          ChallengeClients::HTTP.new(self)
        else
          raise Bullion::Acme::Errors::UnsupportedChallengeType,
                "Challenge type '#{acme_type}' is not supported by Bullion."
        end
      end
    end
  end
end
