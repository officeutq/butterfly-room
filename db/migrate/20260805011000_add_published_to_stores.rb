# frozen_string_literal: true

class AddPublishedToStores < ActiveRecord::Migration[8.1]
  def up
    add_column :stores, :published, :boolean, null: false, default: false
    add_index :stores, :published

    execute "UPDATE stores SET published = TRUE"
  end

  def down
    remove_index :stores, :published
    remove_column :stores, :published
  end
end
