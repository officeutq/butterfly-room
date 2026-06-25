class CreateSupportInquiries < ActiveRecord::Migration[8.1]
  def change
    create_table :support_inquiries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store, foreign_key: true
      t.integer :category, null: false
      t.integer :status, null: false, default: 0
      t.string :subject, null: false
      t.string :reply_email, null: false
      t.string :name_snapshot, null: false
      t.string :role_snapshot, null: false
      t.string :store_name_snapshot
      t.references :source_comment, foreign_key: { to_table: :comments }
      t.datetime :last_message_at, null: false
      t.integer :last_message_sender_kind, null: false
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :support_inquiries, :status
    add_index :support_inquiries, :category
    add_index :support_inquiries, :last_message_at
    add_index :support_inquiries, [ :user_id, :last_message_at ]

    create_table :support_inquiry_messages do |t|
      t.references :support_inquiry, null: false, foreign_key: true
      t.references :sender_user, null: false, foreign_key: { to_table: :users }
      t.integer :sender_kind, null: false
      t.text :body, null: false
      t.datetime :email_enqueued_at

      t.timestamps
    end

    add_index :support_inquiry_messages,
      [ :support_inquiry_id, :created_at, :id ],
      name: "index_support_inquiry_messages_on_thread_order"
  end
end
