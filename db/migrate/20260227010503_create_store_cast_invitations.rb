class CreateStoreCastInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :store_cast_invitations do |t|
      t.references :store, null: false, foreign_key: true

      t.bigint :invited_by_user_id, null: false
      t.bigint :accepted_by_user_id

      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.text :note

      t.timestamps
    end

    add_foreign_key :store_cast_invitations, :users, column: :invited_by_user_id
    add_foreign_key :store_cast_invitations, :users, column: :accepted_by_user_id

    add_index :store_cast_invitations, :token_digest, unique: true
    add_index :store_cast_invitations, :expires_at
    add_index :store_cast_invitations, :used_at
    add_index :store_cast_invitations, [ :store_id, :created_at ]
  end
end
