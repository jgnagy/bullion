# frozen_string_literal: true

# Index nonce expiry/pruning queries by creation time.
class AddCreatedAtIndexToNonces < ActiveRecord::Migration[8.1]
  def change
    add_index :nonces, :created_at
  end
end
