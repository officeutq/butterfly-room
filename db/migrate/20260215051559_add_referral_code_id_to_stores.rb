class AddReferralCodeIdToStores < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:stores, :referral_code_id)
      add_reference :stores, :referral_code, foreign_key: false, index: false, null: true
    end

    unless index_exists?(:stores, :referral_code_id)
      add_index :stores, :referral_code_id
    end

    unless foreign_key_exists?(:stores, :referral_codes)
      add_foreign_key :stores, :referral_codes
    end
  end

  def down
    remove_foreign_key :stores, :referral_codes if foreign_key_exists?(:stores, :referral_codes)
    remove_index :stores, :referral_code_id if index_exists?(:stores, :referral_code_id)
    remove_reference :stores, :referral_code if column_exists?(:stores, :referral_code_id)
  end
end
