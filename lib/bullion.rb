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
require "jwt/eddsa"
require "ed25519"
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

  # Environments in which Bullion is allowed to fall back to a well-known,
  # development-only passphrase for the CA private key. Every other environment
  # (production, or an unset RACK_ENV) must supply CA_SECRET explicitly.
  DEV_OR_TEST_ENVIRONMENTS = %w[development test].freeze

  # Development/test-only fallback passphrase for the CA private key. This value is
  # deliberately well-known: it exists so that local development and the test suite
  # can boot without extra setup. It is never used when RACK_ENV is something other
  # than "development" or "test".
  DEV_ONLY_SECRET = "SomeS3cret"

  setting :ca, reader: true do
    setting :dir, default: "tmp", constructor: -> { File.expand_path(it) }
    # The passphrase used to decrypt the CA private key. There is deliberately no
    # default here; see {resolve_ca_secret} and {validate_config!}.
    setting :secret
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
    @ca_key ||= load_ca_key
  end

  # Loads the CA private key, decrypting it with the configured passphrase
  # @raise [ConfigError] if the key cannot be decrypted with the configured passphrase
  # @return [OpenSSL::PKey::RSA, OpenSSL::PKey::EC] the decrypted CA private key
  def self.load_ca_key
    pem = File.read(config.ca.key_path)
    begin
      OpenSSL::PKey::RSA.new(pem, config.ca.secret)
    rescue OpenSSL::PKey::RSAError
      OpenSSL::PKey::EC.new(pem, config.ca.secret)
    end
  rescue OpenSSL::PKey::ECError => e
    raise ConfigError,
          "Unable to decrypt the CA private key at #{config.ca.key_path}: check that CA_SECRET " \
          "matches the passphrase used to encrypt the key (#{e.message})"
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

  # Resolves the passphrase used to decrypt the CA private key.
  #
  # An explicitly configured passphrase always wins. When none is given, a
  # development/test-only fallback is used so that local development and the test
  # suite can boot without extra setup. In every other environment (production, or
  # an unset RACK_ENV) this resolves to +nil+ so that {.validate_config!} fails
  # closed instead of silently using a well-known passphrase.
  #
  # @param secret [String, nil] the configured CA_SECRET value, if any
  # @param rack_env [String, nil] the RACK_ENV value, if any
  # @return [String, nil] the passphrase to use, or +nil+ when one is required
  def self.resolve_ca_secret(secret, rack_env = ENV.fetch("RACK_ENV", nil))
    return secret unless secret.nil? || secret.to_s.strip.empty?

    DEV_OR_TEST_ENVIRONMENTS.include?(rack_env) ? DEV_ONLY_SECRET : nil
  end

  # Ensures the passphrase used to decrypt the CA private key is present
  # @raise [ConfigError] if the passphrase is missing, blank, or not a String
  # @return [void]
  def self.validate_ca_secret!
    secret = config.ca.secret
    return if secret.is_a?(String) && !secret.strip.empty?

    raise ConfigError,
          "Missing or invalid CA_SECRET: set the CA_SECRET environment variable to the " \
          "passphrase that decrypts the CA private key at #{config.ca.key_path}"
  end

  # Ensures configuration settings are valid
  # @see https://support.apple.com/en-us/HT211025
  def self.validate_config! # rubocop:disable Metrics/AbcSize
    validate_ca_secret!

    unless File.readable?(config.ca.key_path)
      raise ConfigError,
            "Invalid Key Path: #{config.ca.key_path}"
    end
    unless File.readable?(config.ca.cert_path)
      raise ConfigError,
            "Invalid Cert Path: #{config.ca.cert_path}"
    end
    if config.ca.cert_validity_duration > 60 * 60 * 24 * 397
      raise ConfigError,
            "Cert Validity Too Long"
    end
    if config.ca.cert_validity_duration < 60 * 60 * 24 * 2
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

  # The CA passphrase has no default outside of development and test environments;
  # resolve it here so that an unset CA_SECRET fails closed at boot.
  resolved_secret = Bullion.resolve_ca_secret(ca_secret)
  if resolved_secret == Bullion::DEV_ONLY_SECRET && ca_secret.to_s.strip.empty?
    Bullion::LOGGER.warn(
      "CA_SECRET is not set; using the well-known development-only CA passphrase. Set " \
      "CA_SECRET to a strong passphrase for any non-development deployment."
    )
  end

  config.ca.dir = ca_dir if ca_dir
  config.ca.secret = resolved_secret
  config.ca.key_path = ca_key_path if ca_key_path
  config.ca.cert_path = ca_cert_path if ca_cert_path
  config.ca.domains = ca_domains if ca_domains
  config.ca.cert_validity_duration = cert_dur if cert_dur
  config.db_url = db_url if db_url
  config.nameservers = nameservers if nameservers
end

# Itsi processes each request inside its own Fiber, but all fibers on a thread
# share an ActiveSupport execution context by default. ActiveRecord leases a
# database connection per execution context, so without fiber isolation every
# concurrent request fiber on a thread shares (and races on) the same
# connection. Trilogy detects this and raises Trilogy::SynchronizationError.
# Mirror Itsi's own scheduler_mode hook (which itsi-server 0.2.27 never loads)
# and the Rails 8.1+ default by opting into fiber isolation, honoring Itsi's
# opt-out.
# @see https://github.com/jgnagy/bullion/issues/116
unless ENV["ITSI_DISABLE_AS_AUTO_FIBER_ISOLATION_LEVEL"]
  ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
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

if Bullion::DEV_OR_TEST_ENVIRONMENTS.include?(ENV["RACK_ENV"])
  require "bullion/rspec/challenge_clients/dns"
  require "bullion/rspec/challenge_clients/http"

  Bullion.config.acme.challenge_clients = [
    "Bullion::RSpec::ChallengeClients::DNS",
    "Bullion::RSpec::ChallengeClients::HTTP"
  ]
end
