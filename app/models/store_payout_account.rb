# frozen_string_literal: true

class StorePayoutAccount < ApplicationRecord
  belongs_to :store
  belongs_to :updated_by_user, class_name: "User", optional: true

  enum :payout_method, { manual_bank: 0, stripe_connect: 1 }
  enum :status, { active: 0, inactive: 1 }
  enum :account_type, { ordinary: 0, current: 1 }

  validates :store, presence: true
  validates :payout_method, presence: true
  validates :status, presence: true

  with_options if: :manual_bank? do
    validates :bank_code, presence: true, format: { with: /\A\d{4}\z/ }
    validates :branch_code, presence: true, format: { with: /\A\d{3}\z/ }
    validates :account_type, presence: true
    validates :account_number, presence: true, format: { with: /\A\d{7}\z/ }
    validates :account_holder_kana, presence: true
  end

  with_options if: :stripe_connect? do
    validates :stripe_account_id, presence: true
  end
end
