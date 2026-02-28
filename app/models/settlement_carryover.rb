# frozen_string_literal: true

class SettlementCarryover < ApplicationRecord
  belongs_to :store
  belongs_to :source_settlement, class_name: "Settlement", optional: true
  belongs_to :applied_settlement, class_name: "Settlement", optional: true

  enum :reason, { min_payout_carryover: 0, applied_to_settlement: 1 }

  validates :store, presence: true
  validates :reason, presence: true
  validates :amount_yen, numericality: { other_than: 0 }
end
