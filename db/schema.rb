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

ActiveRecord::Schema[8.1].define(version: 2026_02_28_010157) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
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
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.bigint "current_stream_session_id"
    t.text "description"
    t.string "ivs_stage_arn"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_booths_on_archived_at"
    t.index ["current_stream_session_id"], name: "index_booths_on_current_stream_session_id"
    t.index ["ivs_stage_arn"], name: "index_booths_on_ivs_stage_arn"
    t.index ["store_id", "archived_at"], name: "index_booths_on_store_id_and_archived_at"
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

  create_table "favorite_booths", force: :cascade do |t|
    t.bigint "booth_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["booth_id"], name: "index_favorite_booths_on_booth_id"
    t.index ["user_id", "booth_id"], name: "index_favorite_booths_on_user_id_and_booth_id", unique: true
    t.index ["user_id"], name: "index_favorite_booths_on_user_id"
  end

  create_table "favorite_stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["store_id"], name: "index_favorite_stores_on_store_id"
    t.index ["user_id", "store_id"], name: "index_favorite_stores_on_user_id_and_store_id", unique: true
    t.index ["user_id"], name: "index_favorite_stores_on_user_id"
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

  create_table "referral_codes", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "expires_at"
    t.string "label"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_referral_codes_on_code", unique: true
    t.index ["enabled"], name: "index_referral_codes_on_enabled"
    t.index ["expires_at"], name: "index_referral_codes_on_expires_at"
  end

  create_table "settlement_carryovers", force: :cascade do |t|
    t.bigint "amount_yen", null: false
    t.bigint "applied_settlement_id"
    t.datetime "created_at", null: false
    t.text "note"
    t.datetime "period_from"
    t.datetime "period_to"
    t.integer "reason", null: false
    t.bigint "source_settlement_id"
    t.bigint "store_id", null: false
    t.index ["applied_settlement_id"], name: "index_settlement_carryovers_on_applied_settlement_id"
    t.index ["source_settlement_id"], name: "index_settlement_carryovers_on_source_settlement_id"
    t.index ["store_id", "created_at"], name: "index_settlement_carryovers_on_store_id_created_at"
    t.index ["store_id", "reason", "period_from", "period_to"], name: "uniq_settlement_carryovers_min_payout_store_period", unique: true, where: "(reason = 0)"
    t.index ["store_id"], name: "index_settlement_carryovers_on_store_id"
    t.check_constraint "amount_yen <> 0", name: "settlement_carryovers_amount_non_zero"
  end

  create_table "settlements", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "export_file_key"
    t.string "export_format"
    t.datetime "exported_at"
    t.bigint "exported_by_user_id"
    t.bigint "gross_yen", default: 0, null: false
    t.integer "kind", null: false
    t.string "payout_account_holder_kana"
    t.string "payout_account_number", limit: 7
    t.integer "payout_account_type"
    t.string "payout_bank_code", limit: 4
    t.string "payout_branch_code", limit: 3
    t.datetime "period_from", null: false
    t.datetime "period_to", null: false
    t.bigint "platform_fee_yen", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.bigint "store_share_yen", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_settlements_on_kind"
    t.index ["period_from", "period_to"], name: "index_settlements_on_period_from_and_period_to"
    t.index ["status"], name: "index_settlements_on_status"
    t.index ["store_id", "period_from", "period_to"], name: "uniq_settlements_store_period_exact", unique: true
    t.index ["store_id"], name: "index_settlements_on_store_id"
    t.check_constraint "period_from < period_to", name: "settlements_period_from_before_period_to"
    t.exclusion_constraint "store_id WITH =, tsrange(period_from, period_to) WITH &&", using: :gist, name: "excl_settlements_store_period_no_overlap"
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

  create_table "store_cast_invitations", force: :cascade do |t|
    t.bigint "accepted_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "invited_by_user_id", null: false
    t.text "note"
    t.bigint "store_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.index ["expires_at"], name: "index_store_cast_invitations_on_expires_at"
    t.index ["store_id", "created_at"], name: "index_store_cast_invitations_on_store_id_and_created_at"
    t.index ["store_id"], name: "index_store_cast_invitations_on_store_id"
    t.index ["token_digest"], name: "index_store_cast_invitations_on_token_digest", unique: true
    t.index ["used_at"], name: "index_store_cast_invitations_on_used_at"
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

  create_table "store_payout_accounts", force: :cascade do |t|
    t.string "account_holder_kana", limit: 64
    t.string "account_number", limit: 7
    t.integer "account_type"
    t.string "bank_code", limit: 4
    t.string "branch_code", limit: 3
    t.datetime "created_at", null: false
    t.integer "payout_method", null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.string "stripe_account_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_user_id"
    t.index ["payout_method"], name: "index_store_payout_accounts_on_payout_method"
    t.index ["status"], name: "index_store_payout_accounts_on_status"
    t.index ["store_id"], name: "index_store_payout_accounts_on_store_id"
    t.index ["store_id"], name: "uniq_store_payout_accounts_active_on_store_id", unique: true, where: "(status = 0)"
  end

  create_table "stores", force: :cascade do |t|
    t.string "area"
    t.integer "business_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "referral_code_id"
    t.datetime "updated_at", null: false
    t.index ["referral_code_id"], name: "index_stores_on_referral_code_id"
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
    t.text "bio"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
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
  add_foreign_key "favorite_booths", "booths"
  add_foreign_key "favorite_booths", "users"
  add_foreign_key "favorite_stores", "stores"
  add_foreign_key "favorite_stores", "users"
  add_foreign_key "presences", "stream_sessions"
  add_foreign_key "presences", "users", column: "customer_user_id"
  add_foreign_key "settlement_carryovers", "settlements", column: "applied_settlement_id"
  add_foreign_key "settlement_carryovers", "settlements", column: "source_settlement_id"
  add_foreign_key "settlement_carryovers", "stores"
  add_foreign_key "settlements", "stores"
  add_foreign_key "settlements", "users", column: "exported_by_user_id"
  add_foreign_key "store_bans", "stores"
  add_foreign_key "store_bans", "users", column: "created_by_store_admin_user_id"
  add_foreign_key "store_bans", "users", column: "customer_user_id"
  add_foreign_key "store_cast_invitations", "stores"
  add_foreign_key "store_cast_invitations", "users", column: "accepted_by_user_id"
  add_foreign_key "store_cast_invitations", "users", column: "invited_by_user_id"
  add_foreign_key "store_ledger_entries", "drink_orders"
  add_foreign_key "store_ledger_entries", "stores"
  add_foreign_key "store_ledger_entries", "stream_sessions"
  add_foreign_key "store_memberships", "stores"
  add_foreign_key "store_memberships", "users"
  add_foreign_key "store_payout_accounts", "stores"
  add_foreign_key "store_payout_accounts", "users", column: "updated_by_user_id"
  add_foreign_key "stores", "referral_codes"
  add_foreign_key "stream_sessions", "booths"
  add_foreign_key "stream_sessions", "stores"
  add_foreign_key "stream_sessions", "users", column: "started_by_cast_user_id"
  add_foreign_key "wallet_purchases", "wallets"
  add_foreign_key "wallet_transactions", "wallets"
  add_foreign_key "wallets", "users", column: "customer_user_id"
end
