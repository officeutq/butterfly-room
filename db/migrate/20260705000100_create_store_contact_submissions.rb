# frozen_string_literal: true

class CreateStoreContactSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :store_contact_submissions do |t|
      t.string :name, null: false, limit: 120
      t.string :store_name, null: false, limit: 120
      t.string :email, null: false, limit: 255
      t.string :phone_number, null: false, limit: 50
      t.text :body
      t.string :contactable_time, limit: 120
      t.string :source, null: false, default: "stores_lp", limit: 50

      t.timestamps
    end

    add_index :store_contact_submissions, :created_at
    add_index :store_contact_submissions, :source
  end
end
