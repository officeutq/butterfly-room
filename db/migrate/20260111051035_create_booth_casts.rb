class CreateBoothCasts < ActiveRecord::Migration[8.1]
  def change
    create_table :booth_casts do |t|
      t.references :booth, null: false, foreign_key: true
      t.references :cast_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :booth_casts, %i[booth_id cast_user_id], unique: true
  end
end
