# frozen_string_literal: true

# Creates the authorizations table
class CreateAuthorizations < ActiveRecord::Migration[6.1]
  def change
    create_table :authorizations do |t|
      t.string :status, null: false, default: 'pending', index: true
      t.timestamp :expires, null: false, index: true
      t.text :identifier, null: false

      t.belongs_to :order

      t.timestamps
    end
  end
end
