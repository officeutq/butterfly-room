class CreateStoreBans < ActiveRecord::Migration[8.1]
  def change
    create_table :store_bans do |t|
      t.references :store, null: false, foreign_key: true
      t.references :customer_user, null: false, foreign_key: { to_table: :users }
      t.text :reason
      t.references :created_by_store_admin_user, null: false, foreign_key: { to_table: :users }

      t.datetime :created_at, null: false
    end

    add_index :store_bans, %i[store_id customer_user_id], unique: true
  end
end
