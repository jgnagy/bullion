# frozen_string_literal: true

RSpec.describe Bullion::Services::CA do
  context "when an unhandled exception occurs" do
    let(:app) do
      Class.new(Bullion::Services::CA) do
        get "/explode" do
          raise "secret internal detail"
        end

        get "/explode_binary" do
          raise "bad bytes: \xFF".b
        end
      end
    end

    let(:log_output) { StringIO.new }
    let(:request_env) { { "rack.errors" => log_output } }

    it "disables Sinatra's raw error dumper" do
      expect(described_class.dump_errors?).to be(false)
    end

    it "returns a generic RFC 7807 problem document instead of the exception" do
      get "/explode", {}, request_env

      expect(last_response.status).to eq(500)
      expect(last_response.content_type).to include("application/problem+json")
      expect(JSON.parse(last_response.body)).to eq(
        "type" => "urn:ietf:params:acme:error:serverInternal",
        "detail" => "Internal server error"
      )
      expect(last_response.body).not_to include("secret internal detail")
    end

    it "logs the full exception message and backtrace" do
      get "/explode", {}, request_env

      expect(log_output.string).to include(
        "secret internal detail",
        "GET /explode",
        "ca_error_handling_spec.rb"
      )
    end

    it "scrubs invalid bytes so logging cannot hide the sanitized response" do
      get "/explode_binary", {}, request_env

      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("bad bytes")
      expect(log_output.string).to include("bad bytes")
      expect(log_output.string.valid_encoding?).to be(true)
    end

    it "sanitizes unparseable JSON request bodies but logs the parser error" do
      env = request_env.merge("CONTENT_TYPE" => "application/json")

      post "/accounts", "{not json", env

      expect(last_response.status).to eq(400)
      expect(last_response.content_type).to include("application/problem+json")
      expect(JSON.parse(last_response.body)).to eq(
        "type" => "urn:ietf:params:acme:error:malformed",
        "detail" => "Request body must be JSON"
      )
      expect(log_output.string).to include("JSON::ParserError")
    end
  end
end
