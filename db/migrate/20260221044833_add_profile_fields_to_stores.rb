class AddProfileFieldsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :description, :text
    add_column :stores, :area, :string
    add_column :stores, :business_type, :integer
  end
end
