# frozen_string_literal: true

module Bullion
  module Models
    # ACMEv2 Nonce model
    class Nonce < ActiveRecord::Base
      # How long a minted nonce stays usable. RFC 8555 does not mandate a
      # lifetime; fifteen minutes is comfortably longer than a client needs
      # to use a freshly minted nonce while keeping stale rows short-lived.
      TTL = 15 * 60

      # Hard ceiling on outstanding nonce rows. A client that mints nonces
      # without consuming them cannot grow the table past this bound.
      MAX_OUTSTANDING = 10_000

      # How often a mint performs the expiry sweep. Sweeping on every request
      # would scan the table needlessly under normal load.
      CLEANUP_INTERVAL = 60

      after_initialize :init_values, unless: :persisted?

      validates_uniqueness_of :token

      def init_values
        self.token ||= SecureRandom.alphanumeric
      end

      # Delete nonces that are older than {TTL}; they can no longer be used.
      def self.clean_up!(now: Time.now)
        where("created_at < ?", now - TTL).delete_all
      end

      # Keep at most +limit+ nonces, deleting the oldest first. This is the
      # hard bound on table growth: once the cap is reached, each mint evicts
      # the oldest outstanding nonce instead of accumulating indefinitely.
      def self.prune!(limit: MAX_OUTSTANDING)
        excess = count - limit
        return unless excess.positive?

        ids = order(:created_at).limit(excess).pluck(:id)
        where(id: ids).delete_all
      end

      # Mint a nonce while keeping the table bounded.
      def self.mint!
        clean_up_if_due!
        prune!
        create.token
      end

      def self.clean_up_if_due!
        now = Time.now
        return if @last_cleanup_at && now - @last_cleanup_at < CLEANUP_INTERVAL

        @last_cleanup_at = now
        clean_up!(now:)
      end
      private_class_method :clean_up_if_due!
    end
  end
end
