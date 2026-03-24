class AddIconKeyToDrinkItems < ActiveRecord::Migration[8.1]
  def change
    add_column :drink_items, :icon_key, :string, null: true
  end
end
