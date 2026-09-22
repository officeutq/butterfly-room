class AddLifecycleToStoreAdminInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :store_admin_invitations, :note, :text
    add_column :store_admin_invitations, :cancelled_at, :datetime
    add_column :store_admin_invitations, :shared_at, :datetime
    add_column :store_admin_invitations, :request_key, :string
    add_index :store_admin_invitations, [ :invited_by_user_id, :request_key ], unique: true
  end
end
