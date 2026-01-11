class CreateBooths < ActiveRecord::Migration[8.1]
  def change
    create_table :booths do |t|
      t.references :store, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :status, null: false
      t.bigint  :current_stream_session_id # FKは後で付ける

      t.timestamps
    end

    add_index :booths, %i[store_id status]
    add_index :booths, :current_stream_session_id
  end
end
