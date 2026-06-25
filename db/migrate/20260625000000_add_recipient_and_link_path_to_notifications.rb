class AddRecipientAndLinkPathToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications,
      :recipient_user,
      foreign_key: { to_table: :users }

    add_column :notifications, :link_path, :string
  end
end
