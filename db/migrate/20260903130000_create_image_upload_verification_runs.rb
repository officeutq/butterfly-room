class CreateImageUploadVerificationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :image_upload_verification_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :source_blob, foreign_key: { to_table: :active_storage_blobs }
      t.references :display_blob, foreign_key: { to_table: :active_storage_blobs }
      t.string :transport, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :crop_data, null: false, default: {}
      t.jsonb :report, null: false, default: {}
      t.datetime :expires_at, null: false
      t.datetime :cleanup_after, null: false
      t.timestamps
    end
    add_index :image_upload_verification_runs, :cleanup_after
  end
end
