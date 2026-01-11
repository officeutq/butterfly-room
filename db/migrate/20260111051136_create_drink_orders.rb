class CreateDrinkOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :drink_orders do |t|
      t.references :store, null: false, foreign_key: true
      t.references :booth, null: false, foreign_key: true
      t.references :stream_session, null: false, foreign_key: true
      t.references :customer_user, null: false, foreign_key: { to_table: :users }
      t.references :drink_item, null: false, foreign_key: true

      t.integer :status, null: false
      t.datetime :consumed_at
      t.datetime :refunded_at

      t.timestamps
    end

    add_index :drink_orders, %i[stream_session_id status created_at id], name: "idx_drink_orders_fifo"
    add_index :drink_orders, %i[customer_user_id created_at], order: { created_at: :desc }
    add_index :drink_orders, %i[store_id status created_at]
    add_index :drink_orders, %i[store_id consumed_at]
  end
end
