class AddLastOnlineAtToBooths < ActiveRecord::Migration[8.1]
  def change
    add_column :booths, :last_online_at, :datetime
    add_index :booths, :last_online_at
  end
end
