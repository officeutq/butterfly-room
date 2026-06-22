class AddRevocationToStoreBans < ActiveRecord::Migration[8.1]
  def up
    add_reference :store_bans, :source_comment, foreign_key: { to_table: :comments }
    add_column :store_bans, :revoked_at, :datetime
    add_reference :store_bans, :revoked_by_user, foreign_key: { to_table: :users }
    add_column :store_bans, :revocation_reason, :text

    remove_index :store_bans, name: "index_store_bans_on_store_id_and_customer_user_id"
    add_index :store_bans,
              %i[store_id customer_user_id],
              unique: true,
              where: "revoked_at IS NULL",
              name: "index_store_bans_on_active_store_and_customer"
  end

  def down
    remove_index :store_bans, name: "index_store_bans_on_active_store_and_customer"

    remove_reference :store_bans, :source_comment, foreign_key: { to_table: :comments }
    remove_reference :store_bans, :revoked_by_user, foreign_key: { to_table: :users }
    remove_column :store_bans, :revoked_at
    remove_column :store_bans, :revocation_reason

    add_index :store_bans, %i[store_id customer_user_id], unique: true
  end
end
