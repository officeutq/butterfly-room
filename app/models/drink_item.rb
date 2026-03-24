# frozen_string_literal: true

class DrinkItem < ApplicationRecord
  ICON_OPTIONS = {
    "special" => {
      label: "スペシャル",
      path: "drink_icons/drink_special.jpg"
    },
    "mug" => {
      label: "マグ",
      path: "drink_icons/drink_mug.jpg"
    },
    "cocktail" => {
      label: "カクテル",
      path: "drink_icons/drink_cocktail.jpg"
    },
    "microphone" => {
      label: "マイク",
      path: "drink_icons/drink_microphone.jpg"
    },
    "camera" => {
      label: "カメラ",
      path: "drink_icons/drink_camera.jpg"
    },
    "angel" => {
      label: "エンジェル",
      path: "drink_icons/drink_angel.jpg"
    },
    "champagne" => {
      label: "シャンパン",
      path: "drink_icons/drink_champagne.jpg"
    }
  }.freeze

  belongs_to :store

  validates :name, presence: true
  validates :price_points, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true }
  validates :icon_key, inclusion: { in: ICON_OPTIONS.keys }, allow_blank: true

  scope :enabled_only, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }
end
