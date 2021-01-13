# frozen_string_literal: true

# \ -s puma

require 'bullion'
Bullion.validate_config!

require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

use Rack::ShowExceptions
use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter

# Prometheus metrics are on /metrics
mappings = {
  '/ping' => Bullion::Services::Ping.new,
  '/acme' => Bullion::Services::CA.new
}

run Rack::URLMap.new(mappings)
