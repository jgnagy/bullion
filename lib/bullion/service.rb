# frozen_string_literal: true

module Bullion
  # Parent class for API services
  class Service < Sinatra::Base
    register Sinatra::ActiveRecordExtension
    helpers Sinatra::CustomLogger

    configure do
      set :protection, except: :http_origin
      set :host_authorization, permitted_hosts: []
      set :logging, true
      set :logger, Bullion::LOGGER
      set :database, Bullion.config.db_url
      set :show_exceptions, false
      # This service logs unhandled exceptions itself. Sinatra's dump_errors!
      # renders the raw exception message and can raise on invalid bytes before
      # our handler runs, so keep it off in every environment.
      set :dump_errors, false
    end

    before do
      # Sets up a useful variable (@json_body) for accessing a parsed request body
      if request.content_type&.include?("json") && !request.body.read.empty?
        request.body.rewind
        @json_body = JSON.parse(request.body.read, symbolize_names: true)
      end
    rescue StandardError => e
      write_service_log(
        "WARN",
        "Rejected malformed request body: #{e.class}: #{safe_exception_message(e)}"
      )
      content_type "application/problem+json"
      halt(400, {
        type: "urn:ietf:params:acme:error:malformed",
        detail: "Request body must be JSON"
      }.to_json)
    end

    error do
      e = env["sinatra.error"]
      log_unhandled_exception(e)

      status 500
      content_type "application/problem+json"
      {
        type: "urn:ietf:params:acme:error:serverInternal",
        detail: "Internal server error"
      }.to_json
    end

    private

    # Writes the full exception detail (message, backtrace, and causes) to the
    # server log. The text is force-encoded and scrubbed so an exception whose
    # message contains invalid bytes cannot make the logger raise (which would
    # turn the sanitized 500 into an empty response and lose the detail).
    def log_unhandled_exception(exception)
      detail = begin
        exception.full_message(highlight: false)
      rescue StandardError
        "#{exception.class}: #{safe_exception_message(exception)}\n" \
        "#{Array(exception.backtrace).join("\n")}"
      end

      write_exception_log(
        "Unhandled exception while handling #{request.request_method} #{request.path}:\n#{detail}"
      )
    end

    # Returns a valid UTF-8 exception message. Interpolating a binary message
    # with invalid bytes into a UTF-8 string can itself raise, so normalize it
    # before it reaches any string concatenation.
    def safe_exception_message(exception)
      exception.message.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    end

    def write_exception_log(text)
      write_service_log("ERROR", text)
    end

    # Prefer Rack's error stream: Itsi wires it to its own log pipeline, while
    # a Logger captured at boot can point at a worker's closed/inherited stream.
    def write_service_log(level, text)
      message = text.dup.force_encoding(Encoding::UTF_8).scrub("?")
      errors = env["rack.errors"]

      if errors.respond_to?(:puts)
        errors.puts("#{level} bullion: #{message}")
      else
        settings.logger.public_send(level.to_s.downcase.to_sym, message)
      end
    rescue StandardError
      # A logging failure must never replace the sanitized client response.
      nil
    end
  end
end
