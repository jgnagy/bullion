# frozen_string_literal: true

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
