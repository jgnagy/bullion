# frozen_string_literal: true

require "bullion/models/account"

# Adds a public_key_hash column to the accounts table, ensuring uniqueness
class AddPublicKeyHashToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :public_key_hash, :string, null: false, limit: 44
    add_index :accounts, :public_key_hash, unique: true

    reversible do |dir|
      dir.up do
        say_with_time "Generating public_key_hash for existing accounts" do
          require "digest"

          Bullion::Models::Account.reset_column_information
          Bullion::Models::Account.find_each do |account|
            digest = Digest::SHA256.base64digest(account.public_key.to_json)
            account.update_column(:public_key_hash, digest)
          end
        end
      end
    end
  end
end
