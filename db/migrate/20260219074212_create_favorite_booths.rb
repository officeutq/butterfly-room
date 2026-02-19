class CreateFavoriteBooths < ActiveRecord::Migration[8.1]
  def change
    create_table :favorite_booths do |t|
      t.references :user, null: false, foreign_key: true
      t.references :booth, null: false, foreign_key: true

      t.timestamps
    end

    add_index :favorite_booths, %i[user_id booth_id], unique: true
  end
end
