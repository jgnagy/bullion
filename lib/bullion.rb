# frozen_string_literal: true

# Standard Library requirements
require 'base64'
require 'resolv'
require 'securerandom'
require 'time'
require 'logger'
require 'openssl'

# External requirements
require 'sinatra/base'
require 'sinatra/custom_logger'
require 'mysql2'
require 'sinatra/activerecord'
require 'jwt'
require 'prometheus/client'
require 'httparty'

# The top-level module for Bullion
module Bullion
  class Error < StandardError; end
  class ConfigError < Error; end

  LOGGER = Logger.new($stdout)

  # Config through environment variables
  CA_DIR       = File.expand_path ENV.fetch('CA_DIR', 'tmp')
  CA_SECRET    = ENV.fetch('CA_SECRET', 'SomeS3cret')
  CA_KEY_PATH  = ENV.fetch('CA_KEY_PATH') { File.join(CA_DIR, 'tls.key') }
  CA_CERT_PATH = ENV.fetch('CA_CERT_PATH') { File.join(CA_DIR, 'tls.crt') }
  CA_DOMAINS   = ENV.fetch('CA_DOMAINS', 'example.com').split(',')

  # Set up log level
  LOGGER.level = ENV.fetch('LOG_LEVEL', :warn)

  # 90 days cert expiration
  CERT_VALIDITY_DURATION = Integer(
    ENV.fetch('CERT_VALIDITY_DURATION', 60 * 60 * 24 * 30 * 3)
  )

  DB_CONNECTION_SETTINGS =
    ENV['DATABASE_URL'] || {
      adapter: 'mysql2',
      database: ENV.fetch('DB_NAME', 'bullion'),
      encoding: ENV.fetch('DB_ENCODING', 'utf8mb4'),
      pool: Integer(ENV.fetch('MAX_THREADS', 32)),
      username: ENV.fetch('DB_USERNAME', 'root'),
      password: ENV['DB_PASSWORD'],
      host: ENV.fetch('DB_HOST', 'localhost')
    }
  DB_CONNECTION_SETTINGS.freeze

  NAMESERVERS = ENV.fetch('DNS01_NAMESERVERS', '8.8.8.8').split(',')

  MetricsRegistry = Prometheus::Client.registry

  def self.ca_key
    @ca_key ||= OpenSSL::PKey::RSA.new(File.read(CA_KEY_PATH), CA_SECRET)
  end

  def self.ca_cert
    @ca_cert ||= OpenSSL::X509::Certificate.new(File.read(CA_CERT_PATH))
  end

  def self.rotate_keys!
    @ca_key = nil
    @ca_cert = nil
    ca_key
    ca_cert
    true
  end

  # Ensures configuration settings are valid
  # @see https://support.apple.com/en-us/HT211025
  def self.validate_config!
    raise ConfigError, 'Invalid Key Passphrase' unless CA_SECRET.is_a?(String)
    raise ConfigError, "Invalid Key Path: #{CA_KEY_PATH}" unless File.readable?(CA_KEY_PATH)
    raise ConfigError, "Invalid Cert Path: #{CA_CERT_PATH}" unless File.readable?(CA_CERT_PATH)
    raise ConfigError, 'Cert Validity Too Long' if CERT_VALIDITY_DURATION > 60 * 60 * 24 * 397
    raise ConfigError, 'Cert Validity Too Short' if CERT_VALIDITY_DURATION < 60 * 60 * 24 * 2
  end
end

# Internal requirements
require 'bullion/version'
require 'bullion/acme/error'
require 'bullion/helpers/acme'
require 'bullion/helpers/service'
require 'bullion/helpers/ssl'
require 'bullion/models'
require 'bullion/service'
require 'bullion/services/ping'
require 'bullion/services/ca'
require 'bullion/challenge_client'
require 'bullion/challenge_clients/dns'
require 'bullion/challenge_clients/http'
