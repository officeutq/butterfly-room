class AddUniqueIndexToBoothCastsBoothId < ActiveRecord::Migration[8.1]
  def up
    # t.references により既に booth_id の非unique index が存在するため、置き換える
    if index_exists?(:booth_casts, :booth_id, name: "index_booth_casts_on_booth_id")
      remove_index :booth_casts, name: "index_booth_casts_on_booth_id"
    elsif index_exists?(:booth_casts, :booth_id)
      remove_index :booth_casts, :booth_id
    end

    add_index :booth_casts, :booth_id, unique: true, name: "index_booth_casts_on_booth_id"
  end

  def down
    remove_index :booth_casts, name: "index_booth_casts_on_booth_id" if index_exists?(:booth_casts, :booth_id, name: "index_booth_casts_on_booth_id")
    add_index :booth_casts, :booth_id, name: "index_booth_casts_on_booth_id"
  end
end
