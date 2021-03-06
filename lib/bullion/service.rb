# frozen_string_literal: true

module Bullion
  # Parent class for API services
  class Service < Sinatra::Base
    register Sinatra::ActiveRecordExtension
    helpers Sinatra::CustomLogger

    configure do
      set :protection, except: :http_origin
      set :logging, true
      set :logger, Bullion::LOGGER
      set :database, DB_CONNECTION_SETTINGS
    end

    before do
      # Sets up a useful variable (@json_body) for accessing a parsed request body
      if request.content_type&.include?('json') && !request.body.to_s.empty?
        request.body.rewind
        @json_body = JSON.parse(request.body.read, symbolize_names: true)
      end
    rescue StandardError => e
      halt(400, { error: "Request must be JSON: #{e.message}" }.to_json)
    end
  end
end
