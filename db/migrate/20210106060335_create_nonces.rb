# frozen_string_literal: true

# Creates the nonces table
class CreateNonces < ActiveRecord::Migration[6.1]
  def change
    create_table :nonces do |t|
      t.string :token, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
