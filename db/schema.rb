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

ActiveRecord::Schema[8.1].define(version: 2026_02_07_055613) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "booth_casts", force: :cascade do |t|
    t.bigint "booth_id", null: false
    t.bigint "cast_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booth_id", "cast_user_id"], name: "index_booth_casts_on_booth_id_and_cast_user_id", unique: true
    t.index ["booth_id"], name: "index_booth_casts_on_booth_id"
    t.index ["cast_user_id"], name: "index_booth_casts_on_cast_user_id"
  end

  create_table "booths", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_stream_session_id"
    t.text "description"
    t.string "ivs_stage_arn"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_stream_session_id"], name: "index_booths_on_current_stream_session_id"
    t.index ["ivs_stage_arn"], name: "index_booths_on_ivs_stage_arn"
    t.index ["store_id", "status"], name: "index_booths_on_store_id_and_status"
    t.index ["store_id"], name: "index_booths_on_store_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "booth_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "stream_session_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["booth_id", "created_at"], name: "index_comments_on_booth_id_and_created_at"
    t.index ["booth_id"], name: "index_comments_on_booth_id"
    t.index ["stream_session_id", "created_at"], name: "index_comments_on_stream_session_id_and_created_at"
    t.index ["stream_session_id"], name: "index_comments_on_stream_session_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "drink_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_points", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["store_id", "enabled", "position"], name: "index_drink_items_on_store_id_and_enabled_and_position"
    t.index ["store_id"], name: "index_drink_items_on_store_id"
    t.check_constraint "price_points > 0", name: "drink_items_price_points_positive"
  end

  create_table "drink_orders", force: :cascade do |t|
    t.bigint "booth_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.bigint "customer_user_id", null: false
    t.bigint "drink_item_id", null: false
    t.datetime "refunded_at"
    t.integer "status", null: false
    t.bigint "store_id", null: false
    t.bigint "stream_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booth_id"], name: "index_drink_orders_on_booth_id"
    t.index ["customer_user_id", "created_at"], name: "index_drink_orders_on_customer_user_id_and_created_at", order: { created_at: :desc }
    t.index ["customer_user_id"], name: "index_drink_orders_on_customer_user_id"
    t.index ["drink_item_id"], name: "index_drink_orders_on_drink_item_id"
    t.index ["store_id", "consumed_at"], name: "index_drink_orders_on_store_id_and_consumed_at"
    t.index ["store_id", "status", "created_at"], name: "index_drink_orders_on_store_id_and_status_and_created_at"
    t.index ["store_id"], name: "index_drink_orders_on_store_id"
    t.index ["stream_session_id", "status", "created_at", "id"], name: "idx_drink_orders_fifo"
    t.index ["stream_session_id"], name: "index_drink_orders_on_stream_session_id"
  end

  create_table "presences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_user_id", null: false
    t.datetime "joined_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "left_at"
    t.bigint "stream_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_user_id"], name: "index_presences_on_customer_user_id"
    t.index ["stream_session_id", "customer_user_id", "joined_at"], name: "idx_on_stream_session_id_customer_user_id_joined_at_fa01847cc8", unique: true
    t.index ["stream_session_id", "last_seen_at"], name: "index_presences_on_stream_session_id_and_last_seen_at"
    t.index ["stream_session_id", "left_at"], name: "index_presences_on_stream_session_id_and_left_at"
    t.index ["stream_session_id"], name: "index_presences_on_stream_session_id"
  end

  create_table "store_bans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_store_admin_user_id", null: false
    t.bigint "customer_user_id", null: false
    t.text "reason"
    t.bigint "store_id", null: false
    t.index ["created_by_store_admin_user_id"], name: "index_store_bans_on_created_by_store_admin_user_id"
    t.index ["customer_user_id"], name: "index_store_bans_on_customer_user_id"
    t.index ["store_id", "customer_user_id"], name: "index_store_bans_on_store_id_and_customer_user_id", unique: true
    t.index ["store_id"], name: "index_store_bans_on_store_id"
  end

  create_table "store_ledger_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "drink_order_id", null: false
    t.datetime "occurred_at", null: false
    t.integer "points", null: false
    t.bigint "store_id", null: false
    t.bigint "stream_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["drink_order_id"], name: "index_store_ledger_entries_on_drink_order_id", unique: true
    t.index ["store_id", "occurred_at"], name: "index_store_ledger_entries_on_store_id_and_occurred_at", order: { occurred_at: :desc }
    t.index ["store_id"], name: "index_store_ledger_entries_on_store_id"
    t.index ["stream_session_id"], name: "index_store_ledger_entries_on_stream_session_id"
    t.check_constraint "points > 0", name: "store_ledger_entries_points_positive"
  end

  create_table "store_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "membership_role", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_id", "membership_role"], name: "index_store_memberships_on_store_id_and_membership_role"
    t.index ["store_id", "user_id", "membership_role"], name: "idx_on_store_id_user_id_membership_role_e547f6ebfa", unique: true
    t.index ["store_id"], name: "index_store_memberships_on_store_id"
    t.index ["user_id"], name: "index_store_memberships_on_user_id"
  end

  create_table "stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stream_sessions", force: :cascade do |t|
    t.bigint "booth_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "ivs_stage_arn"
    t.datetime "started_at", null: false
    t.bigint "started_by_cast_user_id", null: false
    t.integer "status", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booth_id", "started_at"], name: "index_stream_sessions_on_booth_id_and_started_at"
    t.index ["booth_id"], name: "index_stream_sessions_on_booth_id"
    t.index ["ended_at"], name: "index_stream_sessions_on_ended_at"
    t.index ["ivs_stage_arn"], name: "index_stream_sessions_on_ivs_stage_arn"
    t.index ["started_by_cast_user_id"], name: "index_stream_sessions_on_started_by_cast_user_id"
    t.index ["store_id", "started_at"], name: "index_stream_sessions_on_store_id_and_started_at"
    t.index ["store_id"], name: "index_stream_sessions_on_store_id"
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "livemode"
    t.jsonb "payload"
    t.datetime "received_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_stripe_webhook_events_on_event_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "wallet_purchases", force: :cascade do |t|
    t.bigint "booth_id"
    t.datetime "created_at", null: false
    t.datetime "credited_at"
    t.datetime "paid_at"
    t.integer "points", null: false
    t.integer "status", default: 0, null: false
    t.string "stripe_checkout_session_id"
    t.string "stripe_customer_id"
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["booth_id"], name: "index_wallet_purchases_on_booth_id"
    t.index ["stripe_checkout_session_id"], name: "index_wallet_purchases_on_stripe_checkout_session_id", unique: true
    t.index ["wallet_id"], name: "index_wallet_purchases_on_wallet_id"
  end

  create_table "wallet_transactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.datetime "occurred_at", null: false
    t.integer "points", null: false
    t.bigint "ref_id"
    t.string "ref_type"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["ref_type", "ref_id"], name: "index_wallet_transactions_on_ref_type_and_ref_id"
    t.index ["wallet_id", "occurred_at"], name: "index_wallet_transactions_on_wallet_id_and_occurred_at", order: { occurred_at: :desc }
    t.index ["wallet_id"], name: "index_wallet_transactions_on_wallet_id"
  end

  create_table "wallets", force: :cascade do |t|
    t.integer "available_points", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "customer_user_id", null: false
    t.integer "reserved_points", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_user_id"], name: "index_wallets_on_customer_user_id", unique: true
    t.check_constraint "available_points >= 0", name: "wallets_available_points_non_negative"
    t.check_constraint "reserved_points >= 0", name: "wallets_reserved_points_non_negative"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "booth_casts", "booths"
  add_foreign_key "booth_casts", "users", column: "cast_user_id"
  add_foreign_key "booths", "stores"
  add_foreign_key "booths", "stream_sessions", column: "current_stream_session_id"
  add_foreign_key "comments", "booths"
  add_foreign_key "comments", "stream_sessions"
  add_foreign_key "comments", "users"
  add_foreign_key "drink_items", "stores"
  add_foreign_key "drink_orders", "booths"
  add_foreign_key "drink_orders", "drink_items"
  add_foreign_key "drink_orders", "stores"
  add_foreign_key "drink_orders", "stream_sessions"
  add_foreign_key "drink_orders", "users", column: "customer_user_id"
  add_foreign_key "presences", "stream_sessions"
  add_foreign_key "presences", "users", column: "customer_user_id"
  add_foreign_key "store_bans", "stores"
  add_foreign_key "store_bans", "users", column: "created_by_store_admin_user_id"
  add_foreign_key "store_bans", "users", column: "customer_user_id"
  add_foreign_key "store_ledger_entries", "drink_orders"
  add_foreign_key "store_ledger_entries", "stores"
  add_foreign_key "store_ledger_entries", "stream_sessions"
  add_foreign_key "store_memberships", "stores"
  add_foreign_key "store_memberships", "users"
  add_foreign_key "stream_sessions", "booths"
  add_foreign_key "stream_sessions", "stores"
  add_foreign_key "stream_sessions", "users", column: "started_by_cast_user_id"
  add_foreign_key "wallet_purchases", "wallets"
  add_foreign_key "wallet_transactions", "wallets"
  add_foreign_key "wallets", "users", column: "customer_user_id"
end
