# frozen_string_literal: true

class DrinkItem < ApplicationRecord
  CUSTOM_ICON_ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
  ].freeze
  CUSTOM_ICON_MAX_BYTE_SIZE = 2.megabytes

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
  has_one_attached :custom_icon

  before_validation :normalize_icon_key

  validates :name, presence: true
  validates :price_points, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true }
  validates :icon_key, inclusion: { in: ICON_OPTIONS.keys }, allow_blank: true
  validate :custom_icon_content_type
  validate :custom_icon_byte_size

  scope :enabled_only, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  private

  def normalize_icon_key
    self.icon_key = nil if icon_key.blank?
  end

  def custom_icon_content_type
    return unless custom_icon.attached?

    content_type = custom_icon.blob.content_type.to_s
    return if CUSTOM_ICON_ALLOWED_CONTENT_TYPES.include?(content_type)

    errors.add(:custom_icon, "はJPEG / PNG / WebP のみ使用できます")
  end

  def custom_icon_byte_size
    return unless custom_icon.attached?
    return if custom_icon.blob.byte_size <= CUSTOM_ICON_MAX_BYTE_SIZE

    errors.add(:custom_icon, "は2MB以下にしてください")
  end
end
