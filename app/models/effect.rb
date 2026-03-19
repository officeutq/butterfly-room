# frozen_string_literal: true

class Effect < ApplicationRecord
  validates :name, presence: true
  validates :key, presence: true, uniqueness: true
  validates :zip_filename, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true }

  scope :enabled_only, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }
end
