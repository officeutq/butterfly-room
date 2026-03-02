class AddIssuedUrlToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :store_cast_invitations, :issued_url, :text
    add_index  :store_cast_invitations, :issued_url

    add_column :store_admin_invitations, :issued_url, :text
    add_index  :store_admin_invitations, :issued_url
  end
end
