class AddJpBankFieldsToStorePayoutAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :store_payout_accounts, :input_account_kind, :integer, default: 0, null: false
    add_column :store_payout_accounts, :jp_bank_symbol, :string, limit: 5
    add_column :store_payout_accounts, :jp_bank_number, :string, limit: 8

    add_index :store_payout_accounts, :input_account_kind
  end
end
