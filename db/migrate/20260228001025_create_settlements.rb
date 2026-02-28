class CreateSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :settlements do |t|
      t.references :store, null: false, foreign_key: true

      # --- Period (JST handled at app level) ---
      t.datetime :period_from, null: false
      t.datetime :period_to, null: false

      # --- Kind / Status ---
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0

      # --- Amounts (yen) ---
      t.bigint :gross_yen, null: false, default: 0
      t.bigint :store_share_yen, null: false, default: 0
      t.bigint :platform_fee_yen, null: false, default: 0

      # --- Audit times ---
      t.datetime :confirmed_at
      t.datetime :exported_at
      t.bigint :exported_by_user_id

      # --- Export info ---
      t.string :export_format
      t.string :export_file_key

      # --- Payout snapshot (fixed at export time) ---
      t.string  :payout_bank_code, limit: 4
      t.string  :payout_branch_code, limit: 3
      t.integer :payout_account_type
      t.string  :payout_account_number, limit: 7
      t.string  :payout_account_holder_kana

      t.timestamps
    end

    add_foreign_key :settlements, :users, column: :exported_by_user_id

    # --- Constraints ---
    add_check_constraint :settlements, "period_from < period_to", name: "settlements_period_from_before_period_to"

    add_index :settlements, [ :store_id, :period_from, :period_to ],
              unique: true,
              name: "uniq_settlements_store_period_exact"

    # Reference indexes
    add_index :settlements, :status
    add_index :settlements, :kind
    add_index :settlements, [ :period_from, :period_to ]

    # Overlap guard: same store cannot have overlapping periods ([from, to))
    # Requires btree_gist extension for "store_id WITH =" in gist
    add_exclusion_constraint :settlements,
      "store_id WITH =, tsrange(period_from, period_to) WITH &&",
      using: :gist,
      name: "excl_settlements_store_period_no_overlap"
  end
end
