class CreateCommentReports < ActiveRecord::Migration[8.1]
  def change
    create_table :comment_reports do |t|
      t.references :comment, null: false, foreign_key: true
      t.references :reporter_user, null: false, foreign_key: { to_table: :users }
      t.references :reported_user, null: false, foreign_key: { to_table: :users }
      t.references :store, null: false, foreign_key: true
      t.references :booth, null: false, foreign_key: true
      t.references :stream_session, null: false, foreign_key: true
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :comment_reports, [ :comment_id, :reporter_user_id ], unique: true
  end
end
