# frozen_string_literal: true

class SettlementExport < ApplicationRecord
  belongs_to :generated_by_user, class_name: "User"

  has_one_attached :file

  enum :format, { sbi_furikomi_csv: 0 }

  validates :generated_by_user, presence: true
  validates :format, presence: true
  validates :file_seq, numericality: { greater_than_or_equal_to: 1 }
  validates :record_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_amount_yen, numericality: { greater_than_or_equal_to: 0 }
end
