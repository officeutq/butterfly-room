class AddArchivedAtToBooths < ActiveRecord::Migration[8.1]
  def change
    add_column :booths, :archived_at, :datetime

    add_index :booths, :archived_at
    add_index :booths, %i[store_id archived_at]
  end
end
