# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Order model
    class Order < ActiveRecord::Base
      serialize :identifiers, JSON

      after_initialize :init_values, unless: :persisted?

      belongs_to :account
      has_many :authorizations

      validates :status, inclusion: { in: %w[invalid pending ready processing valid] }

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

      def certificate
        Certificate.find(certificate_id)
      end
    end
  end
end
