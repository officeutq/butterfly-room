class CreatePhoneVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :phone_verifications do |t|
      t.references :user, null: true, foreign_key: true

      t.string :phone_number, null: false
      t.string :purpose, null: false
      t.string :otp_code_digest, null: false

      t.datetime :expires_at, null: false
      t.datetime :last_sent_at, null: false

      t.integer :attempts_count, null: false, default: 0

      t.datetime :verified_at
      t.datetime :consumed_at
      t.datetime :invalidated_at

      t.timestamps
    end

    add_index :phone_verifications, :phone_number
    add_index :phone_verifications, :purpose
    add_index :phone_verifications, %i[phone_number purpose created_at], name: "index_phone_verifications_on_phone_and_purpose_and_created_at"

    add_check_constraint :phone_verifications,
                         "attempts_count >= 0",
                         name: "phone_verifications_attempts_count_non_negative"
  end
end
