class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.integer :role, null: false
      t.string  :display_name

      t.timestamps
    end

    add_index :users, :role
  end
end
