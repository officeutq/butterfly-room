class CreateStoreLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :store_ledger_entries do |t|
      t.references :store, null: false, foreign_key: true
      t.references :stream_session, null: false, foreign_key: true
      t.references :drink_order, null: false, foreign_key: true
      t.integer :points, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :store_ledger_entries, %i[store_id occurred_at], order: { occurred_at: :desc }

    add_check_constraint :store_ledger_entries, "points > 0", name: "store_ledger_entries_points_positive"
  end
end
