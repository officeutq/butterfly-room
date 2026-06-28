# frozen_string_literal: true

class Settlement < ApplicationRecord
  IMMUTABLE_AFTER_CONFIRMED_ATTRIBUTES = %w[
    period_from
    period_to
    gross_yen
    store_share_yen
    platform_fee_yen
  ].freeze

  belongs_to :store
  belongs_to :exported_by_user, class_name: "User", optional: true
  belongs_to :paid_by_user, class_name: "User", optional: true
  has_many :settlement_events, dependent: :destroy

  enum :kind, { monthly: 0, manual: 1 }
  enum :status, { draft: 0, confirmed: 1, exported: 2, paid: 3 }
  enum :payout_account_type, { ordinary: 0, current: 1 }

  validates :store, presence: true
  validates :period_from, presence: true
  validates :period_to, presence: true
  validate :period_range_validation

  validates :gross_yen, :store_share_yen, :platform_fee_yen,
            numericality: { greater_than_or_equal_to: 0 }
  validate :immutable_attributes_after_confirmed, if: :persisted?

  # --- Phase1 minimal guardrails (app-side) ---
  with_options if: :confirmed_or_later? do
    validates :confirmed_at, presence: true
  end

  with_options if: :exported_or_later? do
    validates :exported_at, presence: true
    validates :exported_by_user, presence: true
    validates :export_format, presence: true

    validates :payout_bank_code, presence: true
    validates :payout_branch_code, presence: true
    validates :payout_account_type, presence: true
    validates :payout_account_number, presence: true
    validates :payout_account_holder_kana, presence: true
  end

  with_options if: :paid? do
    validates :paid_at, presence: true
  end

  private

  def period_range_validation
    return if period_from.blank? || period_to.blank?

    errors.add(:period_to, "must be after period_from") unless period_from < period_to
  end

  def immutable_attributes_after_confirmed
    return unless confirmed_or_later? || confirmed_or_later_status?(status_in_database)

    IMMUTABLE_AFTER_CONFIRMED_ATTRIBUTES.each do |attribute|
      next unless will_save_change_to_attribute?(attribute)

      errors.add(attribute, "cannot be changed after confirmed")
    end
  end

  def confirmed_or_later_status?(value)
    normalized =
      if value.is_a?(Integer)
        self.class.statuses.key(value)
      else
        value.to_s
      end

    %w[confirmed exported paid].include?(normalized)
  end

  def confirmed_or_later?
    confirmed? || exported? || paid?
  end

  def exported_or_later?
    exported? || paid?
  end
end
