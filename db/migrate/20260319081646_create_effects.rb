class CreateEffects < ActiveRecord::Migration[8.1]
  def change
    create_table :effects do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.string :zip_filename, null: false
      t.string :icon_path
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :effects, :key, unique: true
    add_index :effects, :zip_filename, unique: true
    add_index :effects, %i[enabled position]
  end
end
