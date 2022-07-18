# frozen_string_literal: true

module Bullion
  module RSpec
    module ChallengeClients
      # A test DNS challenge client resolver for RSpec
      class DNS < ::Bullion::ChallengeClients::DNS
        FakeDNSRecord = Struct.new("FakeDNSRecord", :strings)

        def records_for(name, _nameserver = nil)
          return [] unless name == "_acme-challenge.#{identifier}"

          [
            FakeDNSRecord.new(
              digest_value("#{challenge.token}.#{challenge.thumbprint}")
            )
          ]
        end
      end
    end
  end
end
