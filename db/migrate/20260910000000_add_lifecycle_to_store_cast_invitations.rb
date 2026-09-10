class AddLifecycleToStoreCastInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :store_cast_invitations, :cancelled_at, :datetime
    add_column :store_cast_invitations, :shared_at, :datetime
    add_column :store_cast_invitations, :request_key, :string
    add_index :store_cast_invitations, [ :invited_by_user_id, :request_key ], unique: true
  end
end
