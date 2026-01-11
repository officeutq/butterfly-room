class MakeStoreLedgerEntriesDrinkOrderIdUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :store_ledger_entries, :drink_order_id
    add_index :store_ledger_entries, :drink_order_id, unique: true
  end
end
