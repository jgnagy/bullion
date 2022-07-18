# frozen_string_literal: true

# Creates the orders table
class CreateOrders < ActiveRecord::Migration[6.1]
  def change
    create_table :orders do |t|
      t.string :status, null: false, default: "pending", index: true
      t.timestamp :expires, null: false, index: true
      t.text :identifiers, null: false
      t.timestamp :not_before, null: false
      t.timestamp :not_after, null: false
      t.references :certificate, foreign_key: true

      t.belongs_to :account

      t.timestamps
    end
  end
end
