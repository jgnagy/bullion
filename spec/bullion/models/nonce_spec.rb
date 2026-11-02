# frozen_string_literal: true

RSpec.describe Bullion::Models::Nonce do
  subject { described_class.new }

  before { described_class.delete_all }

  it "automatically sets tokens" do
    expect(subject.token).to be_a(String)
  end

  it "cleans up nonces older than the TTL" do
    stale = described_class.create!(created_at: Time.now - described_class::TTL - 1)
    fresh = described_class.create!

    described_class.clean_up!

    expect(described_class.exists?(stale.id)).to be(false)
    expect(described_class.exists?(fresh.id)).to be(true)
  end

  it "keeps only the newest nonces when pruning" do
    oldest = described_class.create!(created_at: Time.now - 120)
    newest = described_class.create!(created_at: Time.now - 60)

    described_class.prune!(limit: 1)

    expect(described_class.pluck(:id)).to eq([newest.id])
    expect(described_class.exists?(oldest.id)).to be(false)
  end

  it "mints a persisted nonce" do
    token = described_class.mint!

    expect(token).to be_a(String)
    expect(described_class.find_by(token:)).to be_present
  end
end
