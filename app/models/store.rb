# frozen_string_literal: true

class Store < ApplicationRecord
  include NormalizedImageAttachment

  belongs_to :referral_code, optional: true

  has_many :booths, dependent: :destroy
  has_many :store_memberships, dependent: :destroy
  has_many :drink_items, dependent: :destroy
  has_many :store_bans, dependent: :destroy
  has_many :favorite_stores, dependent: :destroy
  has_many :store_payout_accounts, dependent: :restrict_with_error
  has_many :settlements, dependent: :restrict_with_error
  has_many :settlement_carryovers, dependent: :restrict_with_error
  has_one :active_payout_account, -> { active }, class_name: "StorePayoutAccount"
  has_one_attached :thumbnail

  enum :business_type, {
    cabaret: 0,
    girls_bar: 1,
    snack: 2,
    lounge: 3,
    concept_cafe: 4,
    other: 5
  }

  validates :name, presence: true
  validates :description, length: { maximum: 1000 }, allow_nil: true
  validates :area, length: { maximum: 50 }, allow_nil: true

  BUSINESS_TYPE_LABELS = {
    cabaret: "キャバクラ",
    girls_bar: "ガールズバー",
    snack: "スナック",
    lounge: "ラウンジ",
    concept_cafe: "コンカフェ",
    other: "その他"
  }.freeze

  def self.business_type_select_options
    business_types.keys.map { |k| [ BUSINESS_TYPE_LABELS[k.to_sym] || k.to_s, k ] }
  end

  def payout_account_configured?
    pa = active_payout_account
    return false if pa.blank?

    if pa.manual_bank?
      pa.bank_code.present? &&
        pa.branch_code.present? &&
        pa.account_type.present? &&
        pa.account_number.present? &&
        pa.account_holder_kana.present?
    elsif pa.stripe_connect?
      pa.stripe_account_id.present?
    else
      false
    end
  end

  def payout_account_unconfigured?
    !payout_account_configured?
  end

  def payout_account_last4
    pa = active_payout_account
    return nil if pa.blank?
    return nil if pa.account_number.blank?

    pa.account_number.to_s.last(4)
  end
end
