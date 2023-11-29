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

      def init_values
        self.expires ||= Time.now + (60 * 60)
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
