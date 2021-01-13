# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Nonce model
    class Nonce < ActiveRecord::Base
      after_initialize :init_values, unless: :persisted?

      validates_uniqueness_of :token

      def init_values
        self.token ||= SecureRandom.alphanumeric
      end

      # Delete old nonces
      def self.clean_up!
        # nonces older than this can safely be deleted
        where('created_at < ?', Time.now - 86_400).delete_all
      end
    end
  end
end
