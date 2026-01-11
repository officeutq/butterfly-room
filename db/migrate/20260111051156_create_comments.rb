class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :stream_session, null: false, foreign_key: true
      t.references :booth, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :comments, %i[stream_session_id created_at]
    add_index :comments, %i[booth_id created_at]
  end
end
