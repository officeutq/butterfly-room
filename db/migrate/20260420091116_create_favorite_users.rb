class CreateFavoriteUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :favorite_users do |t|
      t.references :user, null: false, foreign_key: true
      t.references :target_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :favorite_users, [ :user_id, :target_user_id ], unique: true
  end
end
