class CreateStoreAdminInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :store_admin_invitations do |t|
      t.references :store, null: false, foreign_key: true
      t.references :invited_by_user, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by_user, foreign_key: { to_table: :users }

      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :store_admin_invitations, :token_digest, unique: true
    add_index :store_admin_invitations, :expires_at
    add_index :store_admin_invitations, :used_at
    add_index :store_admin_invitations, %i[store_id created_at]
  end
end
