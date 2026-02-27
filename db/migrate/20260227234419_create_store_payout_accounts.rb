class CreateStorePayoutAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :store_payout_accounts do |t|
      t.references :store, null: false, foreign_key: true

      t.integer :payout_method, null: false
      t.integer :status, null: false, default: 0

      # --- manual_bank (Phase1) ---
      # null制約は method 別必須にするため “DBでは緩く”、モデルで担保する
      t.string  :bank_code, limit: 4
      t.string  :branch_code, limit: 3
      t.integer :account_type
      t.string  :account_number, limit: 7
      t.string  :account_holder_kana, limit: 64

      # --- stripe_connect (Phase2) ---
      t.string :stripe_account_id

      # --- audit ---
      t.bigint :updated_by_user_id

      t.timestamps
    end

    add_foreign_key :store_payout_accounts, :users, column: :updated_by_user_id

    # 参照用インデックス
    add_index :store_payout_accounts, :status
    add_index :store_payout_accounts, :payout_method

    # 「Storeにつき active は1つ」部分ユニーク（PostgreSQL）
    add_index :store_payout_accounts,
              :store_id,
              unique: true,
              where: "status = 0",
              name: "uniq_store_payout_accounts_active_on_store_id"
  end
end
