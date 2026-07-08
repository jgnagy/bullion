# frozen_string_literal: true

RSpec.describe Bullion::Models::Challenge, "#thumbprint" do
  include BullionTest::Helpers

  # Helper to create an account with a given JWK and return a challenge from it
  def challenge_for_key(jwk)
    account = Bullion::Models::Account.create!(
      tos_agreed: true,
      contacts: ["test@example.com"],
      public_key: jwk
    )
    order = account.start_order(identifiers: [{ "type" => "dns", "value" => "test.test.domain" }])
    authorization = order.authorizations.first
    authorization.challenges.where(acme_type: "http-01").first
  end

  def expect_valid_thumbprint(thumbprint)
    expect(thumbprint).to be_a(String)
    expect(thumbprint).to match(/\A[A-Za-z0-9_-]+\z/)
    # RFC 7638 thumbprints are SHA-256 (43 chars in base64url, no padding)
    expect(thumbprint.length).to eq(43)
  end

  # Generate fresh EC keys without memoization issues from spec_helper
  def fresh_ec_key(crv)
    OpenSSL::PKey::EC.generate(ecsda_crv_to_openssl(crv))
  end

  def fresh_ec_jwk(crv)
    ecdsa_public_key_hash(fresh_ec_key(crv), crv)
  end

  # Generate fresh Ed25519 keys without memoization issues
  def fresh_ed25519_key
    OpenSSL::PKey.generate_key("Ed25519")
  end

  def fresh_ed25519_jwk
    eddsa_public_key_hash(fresh_ed25519_key, "Ed25519")
  end

  context "with RSA keys" do
    it "computes a valid base64url thumbprint for a generated RSA key" do
      jwk = rsa_public_key_hash(rsa_key)
      challenge = challenge_for_key(jwk)
      expect_valid_thumbprint(challenge.thumbprint)
    end

    it "lexicographically orders the JWK members before hashing" do
      jwk = rsa_public_key_hash(rsa_key)
      challenge = challenge_for_key(jwk)

      # The thumbprint must use lexicographic key ordering: e, kty, n
      ordered_jwk = { "e" => jwk["e"], "kty" => jwk["kty"], "n" => jwk["n"] }
      expected = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(ordered_jwk.to_json)
      ).sub(/[\s=]*\z/, "")

      expect(challenge.thumbprint).to eq(expected)
    end

    it "produces a deterministic thumbprint for the same key" do
      jwk = rsa_public_key_hash(rsa_key)

      account = Bullion::Models::Account.create!(
        tos_agreed: true,
        contacts: ["deterministic@example.com"],
        public_key: jwk
      )

      order1 = account.start_order(
        identifiers: [{ "type" => "dns", "value" => "det1.test.domain" }]
      )
      order2 = account.start_order(
        identifiers: [{ "type" => "dns", "value" => "det2.test.domain" }]
      )

      challenge1 = order1.authorizations.first.challenges.where(acme_type: "http-01").first
      challenge2 = order2.authorizations.first.challenges.where(acme_type: "http-01").first

      expect(challenge1.thumbprint).to eq(challenge2.thumbprint)
    end
  end

  context "with EC keys" do
    it "computes a valid base64url thumbprint for a P-256 key" do
      expect_valid_thumbprint(challenge_for_key(fresh_ec_jwk("P-256")).thumbprint)
    end

    it "computes a valid base64url thumbprint for a P-384 key" do
      expect_valid_thumbprint(challenge_for_key(fresh_ec_jwk("P-384")).thumbprint)
    end

    it "computes a valid base64url thumbprint for a P-521 key" do
      expect_valid_thumbprint(challenge_for_key(fresh_ec_jwk("P-521")).thumbprint)
    end

    it "lexicographically orders the JWK members before hashing" do
      jwk = fresh_ec_jwk("P-256")
      challenge = challenge_for_key(jwk)

      # EC thumbprint must use ordering: crv, kty, x, y
      ordered = { "crv" => jwk["crv"], "kty" => jwk["kty"],
                  "x" => jwk["x"], "y" => jwk["y"] }
      expected = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(ordered.to_json)
      ).sub(/[\s=]*\z/, "")

      expect(challenge.thumbprint).to eq(expected)
    end

    it "produces different thumbprints for different curves" do
      jwk256 = fresh_ec_jwk("P-256")
      jwk384 = fresh_ec_jwk("P-384")

      expect(challenge_for_key(jwk256).thumbprint)
        .not_to eq(challenge_for_key(jwk384).thumbprint)
    end
  end

  context "with OKP (EdDSA) keys" do
    it "computes a valid base64url thumbprint for an Ed25519 key" do
      expect_valid_thumbprint(challenge_for_key(fresh_ed25519_jwk).thumbprint)
    end

    it "lexicographically orders the JWK members before hashing" do
      jwk = fresh_ed25519_jwk
      challenge = challenge_for_key(jwk)

      # OKP thumbprint must use ordering: crv, kty, x
      ordered = { "crv" => jwk["crv"], "kty" => jwk["kty"], "x" => jwk["x"] }
      expected = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(ordered.to_json)
      ).sub(/[\s=]*\z/, "")

      expect(challenge.thumbprint).to eq(expected)
    end
  end

  context "with unknown key types" do
    it "falls back to sorted JWK members" do
      jwk = { "z" => "value1", "a" => "value2", "kty" => "unknown" }
      challenge = challenge_for_key(jwk)

      # Fallback sorts keys lexicographically: a, kty, z
      ordered = jwk.sort.to_h
      expected = Base64.urlsafe_encode64(
        OpenSSL::Digest::SHA256.digest(ordered.to_json)
      ).sub(/[\s=]*\z/, "")

      expect(challenge.thumbprint).to eq(expected)
    end
  end

  context "when verifying challenges with real thumbprints" do
    it "verifies HTTP-01 challenge content matches token.thumbprint for RSA" do
      jwk = rsa_public_key_hash(rsa_key)
      challenge = challenge_for_key(jwk)

      # The RSpec HTTP challenge client returns "#{token}.#{thumbprint}"
      # and performs_challenge? checks token == challenge.token &&
      # thumbprint == challenge.thumbprint
      client = Bullion::RSpec::ChallengeClients::HTTP.new(challenge)
      expect(client.attempt).to be(true)
    end

    it "verifies HTTP-01 challenge content matches token.thumbprint for EC" do
      jwk = fresh_ec_jwk("P-256")
      challenge = challenge_for_key(jwk)

      client = Bullion::RSpec::ChallengeClients::HTTP.new(challenge)
      expect(client.attempt).to be(true)
    end

    it "verifies DNS-01 challenge content matches SHA256(token.thumbprint) for RSA" do
      jwk = rsa_public_key_hash(rsa_key)
      challenge = challenge_for_key(jwk)

      # The RSpec DNS challenge client returns digest_value("#{token}.#{thumbprint}")
      # and performs_challenge? checks that the DNS value equals the expected digest
      client = Bullion::RSpec::ChallengeClients::DNS.new(challenge)
      expect(client.attempt).to be(true)
    end

    it "verifies DNS-01 challenge content matches SHA256(token.thumbprint) for EC" do
      jwk = fresh_ec_jwk("P-256")
      challenge = challenge_for_key(jwk)

      client = Bullion::RSpec::ChallengeClients::DNS.new(challenge)
      expect(client.attempt).to be(true)
    end

    it "verifies DNS-01 challenge content matches SHA256(token.thumbprint) for Ed25519" do
      jwk = fresh_ed25519_jwk
      challenge = challenge_for_key(jwk)

      client = Bullion::RSpec::ChallengeClients::DNS.new(challenge)
      expect(client.attempt).to be(true)
    end

    it "produces different thumbprints for RSA and EC keys" do
      rsa_jwk = rsa_public_key_hash(rsa_key)
      ec_jwk = fresh_ec_jwk("P-256")

      expect(challenge_for_key(rsa_jwk).thumbprint)
        .not_to eq(challenge_for_key(ec_jwk).thumbprint)
    end
  end

  context "with invalid JWKs" do
    it "handles JWK missing required fields gracefully" do
      # RSA JWK with kty but missing "n" field
      incomplete_jwk = { "kty" => "RSA", "e" => acme_base64("AQAB") }

      account = Bullion::Models::Account.create!(
        tos_agreed: true,
        contacts: ["test@example.com"],
        public_key: incomplete_jwk
      )
      order = account.start_order(identifiers: [{ "type" => "dns",
                                                  "value" => "test.test.domain" }])
      challenge = order.authorizations.first.challenges
                       .where(acme_type: "http-01").first

      # Should return a string even with missing fields (nil values are serialized)
      thumbprint = challenge.thumbprint
      expect(thumbprint).to be_a(String)
      expect(thumbprint.length).to eq(43)
    end

    it "produces different thumbprints for tampered keys" do
      jwk = rsa_public_key_hash(rsa_key)
      original_challenge = challenge_for_key(jwk)
      original_thumbprint = original_challenge.thumbprint

      # Tamper with the "n" field
      tampered_jwk = jwk.dup
      tampered_jwk["n"] = acme_base64("tampered_value")

      tampered_challenge = challenge_for_key(tampered_jwk)
      tampered_thumbprint = tampered_challenge.thumbprint

      # The thumbprints should be different since key material changed
      expect(original_thumbprint).not_to eq(tampered_thumbprint)
    end
  end
end
