# frozen_string_literal: true

# Standard Library requirements
require "base64"
require "resolv"
require "securerandom"
require "time"
require "logger"
require "openssl"
require "bigdecimal"

# External requirements
require "benchmark"
require "dry-configurable"
require "sinatra/base"
require "sinatra/contrib"
require "sinatra/custom_logger"
require "trilogy"
require "sinatra/activerecord"
require "jwt"
require "prometheus/client"
require "httparty"

# The top-level module for Bullion
module Bullion
  extend Dry::Configurable

  class Error < StandardError; end
  class ConfigError < Error; end

  # Set up logging
  LOGGER = Logger.new($stdout)
  LOGGER.level = ENV.fetch("LOG_LEVEL", :warn)

  setting :ca, reader: true do
    setting :dir, default: "tmp", constructor: -> { File.expand_path(it) }
    setting :secret, default: "SomeS3cret"
    setting(
      :key_path,
      default: "tls.key",
      constructor: lambda { |v|
        v.include?("/") ? File.expand_path(v) : File.join(Bullion.config.ca.dir, v)
      }
    )
    setting(
      :cert_path,
      default: "tls.crt",
      constructor: lambda { |v|
        v.include?("/") ? File.expand_path(v) : File.join(Bullion.config.ca.dir, v)
      }
    )
    setting :domains, default: "example.com", constructor: -> { it.split(",") }
    # 90 days cert expiration
    setting :cert_validity_duration, default: 60 * 60 * 24 * 30 * 3, constructor: -> { Integer(it) }
  end

  setting :acme, reader: true do
    setting(
      :challenge_clients,
      default: ["Bullion::ChallengeClients::DNS", "Bullion::ChallengeClients::HTTP"],
      constructor: -> { it.map { |n| Kernel.const_get(n.to_s) } }
    )
  end

  setting :db_url, reader: true

  setting :nameservers, default: [], constructor: -> { it.split(",") }

  MetricsRegistry = Prometheus::Client.registry

  def self.ca_key
    @ca_key ||= OpenSSL::PKey::RSA.new(File.read(config.ca.key_path), config.ca.secret)
  end

  def self.ca_cert_file
    @ca_cert_file ||= File.read(config.ca.cert_path)
  end

  def self.ca_cert
    @ca_cert ||= OpenSSL::X509::Certificate.new(ca_cert_file)
  end

  def self.rotate_keys! # rubocop:disable Naming/PredicateMethod
    @ca_key = nil
    @ca_cert = nil
    ca_key
    ca_cert
    true
  end

  # Ensures configuration settings are valid
  # @see https://support.apple.com/en-us/HT211025
  def self.validate_config! # rubocop:disable Metrics/AbcSize
    raise ConfigError, "Invalid Key Passphrase" unless config.ca.secret.is_a?(String)

    unless File.readable?(config.ca.key_path)
      raise ConfigError,
            "Invalid Key Path: #{config.ca.key_path}"
    end
    unless File.readable?(config.ca.cert_path)
      raise ConfigError,
            "Invalid Cert Path: #{config.ca.cert_path}"
    end
    if 60 * 60 * 24 * 397 < config.ca.cert_validity_duration
      raise ConfigError,
            "Cert Validity Too Long"
    end
    if 60 * 60 * 24 * 2 > config.ca.cert_validity_duration
      raise ConfigError,
            "Cert Validity Too Short"
    end
    raise ConfigError, "Missing DATABASE_URL" unless config.db_url
  end
end

Bullion.configure do |config|
  # Config through environment variables
  ca_dir       = ENV.fetch("CA_DIR", nil)
  ca_secret    = ENV.fetch("CA_SECRET", nil)
  ca_key_path  = ENV.fetch("CA_KEY_PATH", nil)
  ca_cert_path = ENV.fetch("CA_CERT_PATH", nil)
  ca_domains   = ENV.fetch("CA_DOMAINS", nil)
  cert_dur     = ENV.fetch("CERT_VALIDITY_DURATION", nil)
  db_url       = ENV.fetch("DATABASE_URL", nil)
  nameservers  = ENV.fetch("DNS01_NAMESERVERS", nil)

  config.ca.dir = ca_dir if ca_dir
  config.ca.secret = ca_secret if ca_secret
  config.ca.key_path = ca_key_path if ca_key_path
  config.ca.cert_path = ca_cert_path if ca_cert_path
  config.ca.domains = ca_domains if ca_domains
  config.ca.cert_validity_duration = cert_dur if cert_dur
  config.db_url = db_url if db_url
  config.nameservers = nameservers if nameservers
end

# Internal requirements
require "bullion/version"
require "bullion/acme/error"
require "bullion/helpers/acme"
require "bullion/helpers/service"
require "bullion/helpers/ssl"
require "bullion/models"
require "bullion/service"
require "bullion/services/ping"
require "bullion/services/ca"
require "bullion/challenge_client"
require "bullion/challenge_clients/dns"
require "bullion/challenge_clients/http"

if %w[development test].include?(ENV["RACK_ENV"])
  require "bullion/rspec/challenge_clients/dns"
  require "bullion/rspec/challenge_clients/http"

  Bullion.config.acme.challenge_clients = [
    "Bullion::RSpec::ChallengeClients::DNS",
    "Bullion::RSpec::ChallengeClients::HTTP"
  ]
end
