class MakeWalletsCustomerUserIdUnique < ActiveRecord::Migration[8.1]
  def change
    # 既存の非unique index を unique に置き換える
    remove_index :wallets, :customer_user_id
    add_index :wallets, :customer_user_id, unique: true
  end
end
