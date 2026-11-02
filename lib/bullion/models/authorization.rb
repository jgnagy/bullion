# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Authorization model
    class Authorization < ActiveRecord::Base
      serialize :identifier, coder: JSON

      after_initialize :init_values, unless: :persisted?

      belongs_to :order
      has_many :challenges

      validates :status, inclusion: { in: %w[invalid pending ready processing valid deactivated] }

      enum :status, {
        invalid: "invalid",
        pending: "pending",
        ready: "ready",
        processing: "processing",
        valid: "valid",
        deactivated: "deactivated"
      }, suffix: "status"

      def init_values
        self.expires ||= Time.now + (60 * 60)
      end

      # Whether this authorization's lifetime has elapsed. The stored status
      # is deliberately left untouched: clients still see the last persisted
      # status, while issuance and revocation coverage consult
      # #valid_for_issuance?.
      def expired?
        expires <= Time.now
      end

      # Whether this authorization still proves control of its identifier.
      # RFC 8555 carries an "expires" timestamp precisely so a proof stops
      # being honored after its lifetime, even though its stored status has
      # not been rewritten.
      def valid_for_issuance?
        valid_status? && !expired?
      end

      def prep_challenges!
        %w[http-01 dns-01].each do |type|
          chall = Challenge.new
          chall.authorization = self
          chall.acme_type = type

          chall.save
        end
      end
    end
  end
end
