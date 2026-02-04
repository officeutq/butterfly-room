class AddDescriptionToBooths < ActiveRecord::Migration[8.1]
  def change
    add_column :booths, :description, :text, null: true
  end
end
