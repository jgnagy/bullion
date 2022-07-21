# frozen_string_literal: true

RSpec.describe Bullion::Models::Nonce do
  subject do
    described_class.new
  end

  it "automatically sets tokens" do
    expect(subject.token).to be_a(String)
  end

  it "cleans up old nonces" do
    described_class.create!(created_at: Time.now - 90_000)
    current_count = described_class.count
    expect(current_count).to be > 0
    described_class.clean_up!
    expect(described_class.count).to be < current_count
  end
end
