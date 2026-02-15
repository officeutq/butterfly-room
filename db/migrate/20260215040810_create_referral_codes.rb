class CreateReferralCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :referral_codes do |t|
      t.string :code, null: false
      t.string :label
      t.datetime :expires_at
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :referral_codes, :code, unique: true
    add_index :referral_codes, :enabled
    add_index :referral_codes, :expires_at
  end
end
