class CreateSettlementExports < ActiveRecord::Migration[8.1]
  def change
    create_table :settlement_exports do |t|
      t.integer :format, null: false, default: 0
      t.bigint :generated_by_user_id, null: false

      t.integer :file_seq, null: false, default: 1 # 1,2,3...
      t.integer :record_count, null: false, default: 0
      t.bigint :total_amount_yen, null: false, default: 0

      # 任意：生成対象の期間（将来の絞り込み用、今は使わなくてもOK）
      t.datetime :period_from
      t.datetime :period_to

      t.timestamps
    end

    add_foreign_key :settlement_exports, :users, column: :generated_by_user_id
    add_index :settlement_exports, :format
    add_index :settlement_exports, :created_at
  end
end
