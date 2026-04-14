class AddPhoneNumberToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone_number, :string
    add_column :users, :phone_verified_at, :datetime

    add_index :users, :phone_number, unique: true
  end
end
