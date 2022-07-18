# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2021_01_06_060335) do
  create_table "accounts", force: :cascade do |t|
    t.boolean "tos_agreed", default: true, null: false
    t.text "public_key", null: false
    t.text "contacts", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_key"], name: "index_accounts_on_public_key", unique: true
    t.index ["tos_agreed"], name: "index_accounts_on_tos_agreed"
  end

  create_table "authorizations", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.datetime "expires", precision: nil, null: false
    t.text "identifier", null: false
    t.integer "order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires"], name: "index_authorizations_on_expires"
    t.index ["order_id"], name: "index_authorizations_on_order_id"
    t.index ["status"], name: "index_authorizations_on_status"
  end

  create_table "certificates", force: :cascade do |t|
    t.string "subject", null: false
    t.string "csr_fingerprint", null: false
    t.text "data", null: false
    t.text "alternate_names"
    t.string "requester"
    t.boolean "validated", default: false, null: false
    t.bigint "serial", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["csr_fingerprint"], name: "index_certificates_on_csr_fingerprint"
    t.index ["serial"], name: "index_certificates_on_serial", unique: true
    t.index ["subject"], name: "index_certificates_on_subject"
    t.index ["validated"], name: "index_certificates_on_validated"
  end

  create_table "challenges", force: :cascade do |t|
    t.string "acme_type", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires", precision: nil, null: false
    t.string "token", null: false
    t.datetime "validated", precision: nil
    t.integer "authorization_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acme_type"], name: "index_challenges_on_acme_type"
    t.index ["authorization_id"], name: "index_challenges_on_authorization_id"
    t.index ["expires"], name: "index_challenges_on_expires"
    t.index ["status"], name: "index_challenges_on_status"
  end

  create_table "nonces", force: :cascade do |t|
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_nonces_on_token", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.datetime "expires", precision: nil, null: false
    t.text "identifiers", null: false
    t.datetime "not_before", precision: nil, null: false
    t.datetime "not_after", precision: nil, null: false
    t.integer "certificate_id"
    t.integer "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_orders_on_account_id"
    t.index ["certificate_id"], name: "index_orders_on_certificate_id"
    t.index ["expires"], name: "index_orders_on_expires"
    t.index ["status"], name: "index_orders_on_status"
  end

  add_foreign_key "orders", "certificates"
end
