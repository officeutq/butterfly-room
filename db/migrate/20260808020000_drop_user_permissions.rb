# frozen_string_literal: true

class DropUserPermissions < ActiveRecord::Migration[8.1]
  def up
    drop_table :user_permissions
  end

  def down
    create_table :user_permissions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :permission_type, null: false

      t.timestamps
    end

    add_index :user_permissions,
              %i[user_id permission_type],
              unique: true,
              name: "index_user_permissions_on_user_and_type"
  end
end
