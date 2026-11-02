# frozen_string_literal: true

require "bullion"
Bullion.validate_config!

require "prometheus/middleware/collector"
require "prometheus/middleware/exporter"

# Rack::ShowExceptions renders exception messages and backtraces; keep it out
# of production so a request that escapes Sinatra's handlers cannot leak them.
use Rack::ShowExceptions if Bullion::DEV_OR_TEST_ENVIRONMENTS.include?(
  ENV.fetch("RACK_ENV", "development")
)
use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

# Prometheus metrics are on /metrics
mappings = {
  "/ping" => Bullion::Services::Ping.new,
  "/acme" => Bullion::Services::CA.new
}

run Rack::URLMap.new(mappings)
