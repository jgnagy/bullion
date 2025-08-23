# frozen_string_literal: true

# Creates the accounts table
class CreateAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :accounts do |t|
      t.boolean :tos_agreed, null: false, default: true, index: true
      t.text :public_key, null: false
      t.text :contacts, null: false

      t.timestamps
    end
  end
end
