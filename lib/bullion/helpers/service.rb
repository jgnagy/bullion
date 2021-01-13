# frozen_string_literal: true

module Bullion
  module Helpers
    # Sinatra service helper methods
    module Service
      def add_acme_headers(nonce, additional: {})
        headers['Replay-Nonce'] = nonce
        headers['Link'] = "<#{uri('/directory')}>;rel=\"index\""

        additional.each do |name, value|
          headers[name.to_s] = value.to_s
        end
      end
    end
  end
end
