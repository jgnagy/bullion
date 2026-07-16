# frozen_string_literal: true

# Adds revocation tracking columns to the certificates table
class AddRevocationToCertificates < ActiveRecord::Migration[8.0]
  def change
    add_column :certificates, :revoked, :boolean, default: false, null: false
    add_column :certificates, :revoked_at, :datetime
    add_column :certificates, :revocation_reason, :integer
  end
end
