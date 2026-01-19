# frozen_string_literal: true

class DrinkItem < ApplicationRecord
  belongs_to :store

  validates :name, presence: true
  validates :price_points, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true }

  scope :enabled_only, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }
end
