# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Order model
    class Order < ActiveRecord::Base
      serialize :identifiers, coder: JSON

      after_initialize :init_values, unless: :persisted?

      belongs_to :account
      belongs_to :certificate
      has_many :authorizations

      validates :status, inclusion: { in: %w[invalid pending ready processing valid] }

      enum :status, {
        invalid: "invalid",
        pending: "pending",
        ready: "ready",
        processing: "processing",
        valid: "valid"
      }, suffix: "status"

      def init_values
        self.expires ||= Time.now + (60 * 60)
        self.not_before ||= Time.now
        self.not_after ||= Time.now + (60 * 60 * 24 * 90) # 90 days
      end

      def prep_authorizations!
        identifiers.each do |identifier|
          authorization = Authorization.new
          authorization.order = self
          authorization.identifier = identifier

          authorization.save

          authorization.prep_challenges!
        end
      end

      # Used to extract domains from order (mostly for comparison with CSR)
      def domains = identifiers.map { _1["value"] }
    end
  end
end
