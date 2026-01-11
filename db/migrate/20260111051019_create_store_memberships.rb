class CreateStoreMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :store_memberships do |t|
      t.references :store, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.integer :membership_role, null: false

      t.timestamps
    end

    add_index :store_memberships, %i[store_id user_id membership_role], unique: true
    add_index :store_memberships, %i[store_id membership_role]
  end
end
