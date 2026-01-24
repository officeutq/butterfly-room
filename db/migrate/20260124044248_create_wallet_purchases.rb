class CreateWalletPurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :wallet_purchases do |t|
      t.references :wallet, null: false, foreign_key: true
      t.integer :points, null: false

      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.string :stripe_customer_id

      t.bigint :booth_id
      t.integer :status, null: false, default: 0 # pending/paid/credited/canceled/failed

      t.datetime :paid_at
      t.datetime :credited_at

      t.timestamps
    end

    add_index :wallet_purchases, :stripe_checkout_session_id, unique: true
    add_index :wallet_purchases, :booth_id
  end
end
