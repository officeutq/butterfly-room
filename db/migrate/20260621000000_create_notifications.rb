class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :published_at, null: false
      t.references :created_by_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :notifications, :published_at
    add_index :notifications, :enabled

    create_table :notification_tags do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :notification_tags, :name, unique: true

    create_table :notification_taggings do |t|
      t.references :notification, null: false, foreign_key: true
      t.references :notification_tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :notification_taggings,
      [ :notification_id, :notification_tag_id ],
      unique: true,
      name: "index_notification_taggings_uniqueness"

    create_table :notification_reads do |t|
      t.references :notification, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at, null: false

      t.timestamps
    end

    add_index :notification_reads,
      [ :notification_id, :user_id ],
      unique: true,
      name: "index_notification_reads_uniqueness"
  end
end
