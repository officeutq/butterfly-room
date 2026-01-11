class CreateWalletTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :wallet_transactions do |t|
      t.references :wallet, null: false, foreign_key: true
      t.integer :kind, null: false
      t.integer :points, null: false
      t.string  :ref_type
      t.bigint  :ref_id
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :wallet_transactions, %i[wallet_id occurred_at], order: { occurred_at: :desc }
    add_index :wallet_transactions, %i[ref_type ref_id]
  end
end
