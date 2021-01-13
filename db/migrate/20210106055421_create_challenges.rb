# frozen_string_literal: true

# Creates the challenges table
class CreateChallenges < ActiveRecord::Migration[6.1]
  def change
    create_table :challenges do |t|
      t.string :acme_type, null: false, index: true
      t.string :status, null: false, default: :pending, index: true
      t.timestamp :expires, null: false, index: true
      t.string :token, null: false
      t.timestamp :validated

      t.belongs_to :authorization

      t.timestamps
    end
  end
end
