# frozen_string_literal: true

require "open3"

RSpec.describe Bullion do
  it "has a version number" do
    expect(Bullion::VERSION).not_to be_nil
  end

  it "provides access to the CA's private key" do
    expect(described_class.ca_key).to be_an(OpenSSL::PKey::RSA)
  end

  it "provides access to the CA's public key" do
    expect(described_class.ca_cert).to be_an(OpenSSL::X509::Certificate)
  end

  it "validates its configuration" do
    expect { described_class.validate_config! }.not_to raise_exception
  end

  it "supports re-reading keys from the filesystem" do
    expect(described_class.rotate_keys!).to be(true)
  end

  describe "CA secret configuration" do
    let(:project_root) { File.expand_path("..", __dir__) }

    describe ".resolve_ca_secret" do
      it "prefers an explicitly configured passphrase" do
        expect(described_class.resolve_ca_secret("s3cret", "production")).to eq("s3cret")
      end

      it "falls back to the development-only passphrase in development" do
        expect(described_class.resolve_ca_secret(nil, "development")).to eq(Bullion::DEV_ONLY_SECRET)
      end

      it "falls back to the development-only passphrase in test" do
        expect(described_class.resolve_ca_secret(nil, "test")).to eq(Bullion::DEV_ONLY_SECRET)
      end

      it "does not fall back to a well-known passphrase in production" do
        expect(described_class.resolve_ca_secret(nil, "production")).to be_nil
      end

      it "does not fall back to a well-known passphrase when RACK_ENV is unset" do
        expect(described_class.resolve_ca_secret(nil, nil)).to be_nil
      end

      it "treats a blank passphrase as unset" do
        expect(described_class.resolve_ca_secret("", "production")).to be_nil
        expect(described_class.resolve_ca_secret("   ", "development")).to eq(Bullion::DEV_ONLY_SECRET)
      end
    end

    describe ".validate_config!" do
      around do |example|
        original_secret = described_class.config.ca.secret
        example.run
        described_class.config.ca.secret = original_secret
      end

      it "raises a ConfigError naming CA_SECRET when the passphrase is unset" do
        described_class.config.ca.secret = nil
        expect { described_class.validate_config! }.to(
          raise_error(Bullion::ConfigError, /CA_SECRET/)
        )
      end

      it "raises a ConfigError naming CA_SECRET when the passphrase is blank" do
        described_class.config.ca.secret = ""
        expect { described_class.validate_config! }.to(
          raise_error(Bullion::ConfigError, /CA_SECRET/)
        )
      end

      it "raises a ConfigError naming CA_SECRET when the passphrase is not a String" do
        described_class.config.ca.secret = 12_345
        expect { described_class.validate_config! }.to(
          raise_error(Bullion::ConfigError, /CA_SECRET/)
        )
      end

      it "accepts a configured passphrase" do
        described_class.config.ca.secret = "s3cret"
        expect { described_class.validate_config! }.not_to raise_error
      end
    end

    # Booting Bullion runs the configuration load path (resolving CA_SECRET) and
    # then validates it, so these examples boot a real process in a subprocess.
    describe "booting" do
      let(:boot_script) do
        <<~'RUBY'
          require "bullion"
          $stdout.sync = true
          puts "SECRET_SET=#{!Bullion.config.ca.secret.to_s.strip.empty?}"
          puts "DEV_DEFAULT=#{Bullion.config.ca.secret == Bullion::DEV_ONLY_SECRET}"
          begin
            Bullion.validate_config!
            puts "RESULT=booted"
          rescue Bullion::ConfigError => e
            puts "RESULT=config_error"
            warn e.message
            exit 1
          end
        RUBY
      end

      def boot(env = {})
        Open3.capture3(
          {
            "BUNDLE_GEMFILE" => ENV.fetch("BUNDLE_GEMFILE", File.join(project_root, "Gemfile")),
            "RUBYOPT" => "-rbundler/setup",
            "CA_SECRET" => nil
          }.merge(env),
          RbConfig.ruby, "-e", boot_script,
          chdir: project_root
        )
      end

      it "refuses to boot in production when CA_SECRET is unset" do
        stdout, stderr, status = boot("RACK_ENV" => "production")

        expect(status).not_to be_success
        expect(stdout).to include("SECRET_SET=false")
        expect(stdout).to include("DEV_DEFAULT=false")
        expect(stdout).to include("RESULT=config_error")
        expect(stderr).to include("CA_SECRET")
      end

      it "boots in development without CA_SECRET using the development-only passphrase" do
        stdout, stderr, = boot("RACK_ENV" => "development")

        expect(stdout).to include("SECRET_SET=true")
        expect(stdout).to include("DEV_DEFAULT=true")
        expect(stderr).not_to include("Missing or invalid CA_SECRET")
      end

      it "boots in production when CA_SECRET is set" do
        stdout, stderr, = boot("RACK_ENV" => "production", "CA_SECRET" => "s3cret")

        expect(stdout).to include("SECRET_SET=true")
        expect(stdout).to include("DEV_DEFAULT=false")
        expect(stderr).not_to include("Missing or invalid CA_SECRET")
      end
    end
  end

  # Itsi serves each request in its own Fiber, but fibers share a thread.
  # ActiveRecord keys connection leases off ActiveSupport::IsolatedExecutionState,
  # so without fiber isolation concurrent request fibers would share (and race
  # on) a single database connection, which Trilogy rejects with
  # Trilogy::SynchronizationError.
  # @see https://github.com/jgnagy/bullion/issues/116
  describe "fiber-based database isolation" do
    it "uses fiber-level ActiveSupport isolation" do
      expect(ActiveSupport::IsolatedExecutionState.isolation_level).to eq(:fiber)
    end

    it "gives concurrently scheduled fibers distinct execution contexts" do
      require "itsi/scheduler"
      contexts = Queue.new

      Thread.new do
        Fiber.set_scheduler(Itsi::Scheduler.new)
        2.times do
          Fiber.schedule { contexts << ActiveSupport::IsolatedExecutionState.context }
        end
      end.join

      execution_contexts = Array.new(contexts.size) { contexts.pop }

      expect(execution_contexts.uniq.size).to eq(2)
    end
  end
end
