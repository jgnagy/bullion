# frozen_string_literal: true

module Bullion
  module RSpec
    module ChallengeClients
      # A test HTTP challenge client resolver for RSpec
      class HTTP < ::Bullion::ChallengeClients::HTTP
        def retrieve_body(url)
          return "" unless url == "http://#{identifier}/.well-known/acme-challenge/#{challenge.token}"

          "#{challenge.token}.#{challenge.thumbprint}"
        end
      end
    end
  end
end
