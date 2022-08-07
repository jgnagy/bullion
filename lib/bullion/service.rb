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
      set :show_exceptions, false
    end

    before do
      # Sets up a useful variable (@json_body) for accessing a parsed request body
      if request.content_type&.include?("json") && !request.body.read.empty?
        request.body.rewind
        @json_body = JSON.parse(request.body.read, symbolize_names: true)
      end
    rescue StandardError => e
      halt(400, { error: "Request must be JSON: #{e.message}}" }.to_json)
    end

    error do
      content_type :json

      e = env["sinatra.error"]
      resp = { result: "error", message: e.message }
      resp[:trace] = e.full_message if settings.environment.to_s != "production"
      resp.to_json
    end
  end
end
