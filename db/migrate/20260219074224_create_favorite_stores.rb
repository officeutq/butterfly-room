class CreateFavoriteStores < ActiveRecord::Migration[8.1]
  def change
    create_table :favorite_stores do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true

      t.timestamps
    end

    add_index :favorite_stores, %i[user_id store_id], unique: true
  end
end
