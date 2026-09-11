# frozen_string_literal: true

class ChangeLog < ApplicationRecord
  include LogEntry

  TARGET_TYPES = %w[Store Booth].freeze
  ACTIONS = %w[created updated].freeze

  before_validation :sanitize_change_data, on: :create
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, numericality: { only_integer: true, greater_than: 0 }
  validates :action, inclusion: { in: ACTIONS }
  validates :change_data, presence: true
  validate :bounded_change_data

  private

  def sanitize_change_data
    self.change_data = Logs::Sanitizer.change_data(target_type, change_data)
  rescue ArgumentError
    errors.add(:change_data, :invalid)
  end

  def bounded_change_data
    errors.add(:change_data, :invalid) unless change_data.is_a?(Hash) && change_data.to_json.bytesize <= 16_000
  end
end
