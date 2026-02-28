class CreateSettlementCarryovers < ActiveRecord::Migration[8.1]
  def change
    create_table :settlement_carryovers do |t|
      t.references :store, null: false, foreign_key: true

      # Ledger delta (+ / -)
      t.bigint :amount_yen, null: false

      # 0: min_payout_carryover, 1: applied_to_settlement
      t.integer :reason, null: false

      # Idempotency key for min_payout_carryover rows (optional for other reasons)
      t.datetime :period_from
      t.datetime :period_to

      # ★t.references は index を自動で作るので、別途 add_index しない
      t.references :source_settlement, foreign_key: { to_table: :settlements }
      t.references :applied_settlement, foreign_key: { to_table: :settlements }

      t.text :note

      # created_at only (ledger)
      t.datetime :created_at, null: false
    end

    add_index :settlement_carryovers, %i[store_id created_at],
              name: "index_settlement_carryovers_on_store_id_created_at"

    # Prevent double-add for the same store+period when settlement is not created (min payout carryover only)
    add_index :settlement_carryovers, %i[store_id reason period_from period_to],
              unique: true,
              where: "reason = 0",
              name: "uniq_settlement_carryovers_min_payout_store_period"

    add_check_constraint :settlement_carryovers, "amount_yen <> 0",
                         name: "settlement_carryovers_amount_non_zero"
  end
end
