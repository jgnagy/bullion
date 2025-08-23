# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Account model
    class Account < ActiveRecord::Base
      serialize :contacts, coder: JSON
      serialize :public_key, coder: JSON

      validates_uniqueness_of :public_key_hash

      has_many :orders

      before_save :generate_public_key_hash

      def generate_public_key_hash
        digest = Digest::SHA256.base64digest(public_key.to_json)
        self.public_key_hash = digest
      end

      def kid
        id
      end

      def start_order(identifiers:, not_before: nil, not_after: nil)
        order = Order.new
        order.not_before = not_before if not_before
        order.not_after = not_after if not_after
        order.account = self
        order.status = "pending"
        order.identifiers = identifiers
        order.save

        order.prep_authorizations!

        order
      end
    end
  end
end
