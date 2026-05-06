# frozen_string_literal: true

class StorePayoutAccount < ApplicationRecord
  belongs_to :store
  belongs_to :updated_by_user, class_name: "User", optional: true

  enum :payout_method, { manual_bank: 0, stripe_connect: 1 }
  enum :status, { active: 0, inactive: 1 }
  enum :account_type, { ordinary: 0, current: 1 }
  enum :input_account_kind, { bank: 0, jp_bank: 1 }

  before_validation :normalize_jp_bank_account, if: :jp_bank_manual_bank?

  validates :store, presence: true
  validates :payout_method, presence: true
  validates :status, presence: true
  validates :input_account_kind, presence: true

  with_options if: :bank_manual_bank? do
    validates :bank_code, presence: true, format: { with: /\A\d{4}\z/ }
    validates :branch_code, presence: true, format: { with: /\A\d{3}\z/ }
    validates :account_type, presence: true
    validates :account_number, presence: true, format: { with: /\A\d{7}\z/ }
    validates :account_holder_kana, presence: true
  end

  with_options if: :jp_bank_manual_bank? do
    validates :jp_bank_symbol, presence: true, format: { with: /\A1\d{4}\z/ }
    validates :jp_bank_number, presence: true, format: { with: /\A\d{2,8}\z/ }
    validates :account_holder_kana, presence: true
  end

  validate :validate_jp_bank_conversion, if: :jp_bank_manual_bank?

  with_options if: :stripe_connect? do
    validates :stripe_account_id, presence: true
  end

  private

  def bank_manual_bank?
    manual_bank? && bank?
  end

  def jp_bank_manual_bank?
    manual_bank? && jp_bank?
  end

  def normalize_jp_bank_account
    converted =
      PayoutAccounts::JpBankConverter.new(
        symbol: jp_bank_symbol,
        number: jp_bank_number
      ).call

    self.bank_code = converted.bank_code
    self.branch_code = converted.branch_code
    self.account_type = converted.account_type
    self.account_number = converted.account_number
  rescue PayoutAccounts::JpBankConverter::Error
    # 詳細なエラーは各format validationに任せる
  end

  def validate_jp_bank_conversion
    return if jp_bank_symbol.blank? || jp_bank_number.blank?
    return if bank_code.present? &&
              branch_code.present? &&
              account_type.present? &&
              account_number.present?

    errors.add(:base, "ゆうちょ銀行の記号・番号を確認してください")
  end
end
