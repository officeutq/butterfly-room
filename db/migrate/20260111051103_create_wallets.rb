class CreateWallets < ActiveRecord::Migration[8.1]
  def change
    create_table :wallets do |t|
      t.references :customer_user, null: false, foreign_key: { to_table: :users }

      t.integer :available_points, null: false, default: 0
      t.integer :reserved_points,  null: false, default: 0

      t.timestamps
    end

    add_check_constraint :wallets, "available_points >= 0", name: "wallets_available_points_non_negative"
    add_check_constraint :wallets, "reserved_points >= 0",  name: "wallets_reserved_points_non_negative"
  end
end
