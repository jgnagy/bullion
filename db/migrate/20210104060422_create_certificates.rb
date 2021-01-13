# frozen_string_literal: true

# Creates the certificates table
class CreateCertificates < ActiveRecord::Migration[6.1]
  def change
    create_table :certificates do |t|
      t.string :subject, null: false, index: true
      t.string :csr_fingerprint, null: false, index: true
      t.text :data, null: false
      t.text :alternate_names
      t.string :requester
      t.boolean :validated, null: false, default: false, index: true
      t.integer :serial, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
