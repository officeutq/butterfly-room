class CreateDrinkItems < ActiveRecord::Migration[8.1]
  def change
    create_table :drink_items do |t|
      t.references :store, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :price_points, null: false
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :drink_items, %i[store_id enabled position]
    add_check_constraint :drink_items, "price_points > 0", name: "drink_items_price_points_positive"
  end
end
