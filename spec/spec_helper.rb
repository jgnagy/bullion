# frozen_string_literal: true

require "simplecov"
require "bundler/setup"
require "acme-client"

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [SimpleCov::Formatter::HTMLFormatter]
)

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/.bundle/"
end

require "rack/test"
require "bullion"

ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL", nil))
ActiveRecord::Base.logger = Bullion::LOGGER

module BullionTest
  module Helpers
    def acme_base64(content)
      Base64.urlsafe_encode64(content).sub(/[\s=]*$/, "")
    end

    def acme_sign(key, content, hash_alg: "SHA256")
      if key.instance_of?(OpenSSL::PKey::RSA)
        acme_base64 key.sign(OpenSSL::Digest.new(hash_alg), content)
      elsif key.instance_of?(OpenSSL::PKey::EC)
        ecdsa_acme_sign(key, content, hash_alg:)
      else
        raise "Unknown key class"
      end
    end

    def rsa_key(size = 2048)
      @rsa_key ||= OpenSSL::PKey::RSA.new(size)
    end

    def rsa_public_key_hash(key)
      {
        "e" => acme_base64(key.e.to_s(2)),
        "kty" => "RSA",
        "n" => acme_base64(key.public_key.n.to_s(2))
      }
    end

    def ecsda_crv_to_openssl(crv)
      crv_mapping = {
        "P-256" => "prime256v1",
        "P-384" => "secp384r1",
        "P-521" => "secp521r1"
      }
      crv_mapping[crv.to_s]
    end

    def ecdsa_key(crv = "P-256")
      key = OpenSSL::PKey::EC.generate(ecsda_crv_to_openssl(crv))
      @ecdsa_key ||= key
    end

    def ecdsa_public_key_hash(key, crv = "P-256")
      hex_key = key.public_key.to_bn.to_s(16)
      hex_length = hex_key.size - 2
      hex_x = hex_key[2, (hex_length / 2)]
      hex_y = hex_key[(2 + (hex_length / 2)), (hex_length / 2)]
      x = acme_base64(OpenSSL::BN.new([hex_x].pack("H*"), 2).to_s(2))
      y = acme_base64(OpenSSL::BN.new([hex_y].pack("H*"), 2).to_s(2))
      {
        "x" => x,
        "y" => y,
        "kty" => "EC",
        "crv" => crv
      }
    end

    def ecdsa_acme_sign(key, content, hash_alg: "SHA256")
      signed = key.sign(OpenSSL::Digest.new(hash_alg), content)
      seq = OpenSSL::ASN1.decode(signed)
      big_ints = seq.value.map(&:value)
      bytes = (key.group.degree + 7) / 8
      r_val, s_val = big_ints.map { |big_int| big_int.to_s(2).rjust(bytes, "\x00") }
      acme_base64 [r_val, s_val].join
    end
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
