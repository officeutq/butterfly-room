class AddKindAndMetadataToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :kind, :string, null: false, default: "chat"
    add_column :comments, :metadata, :jsonb, null: false, default: {}

    change_column_null :comments, :body, true
  end
end
