# frozen_string_literal: true

class FilepondTestUpload < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/heic
    image/heif
  ].freeze

  has_one_attached :image

  validates :title, length: { maximum: 100 }, allow_blank: true
  validate :image_presence
  validate :image_content_type

  private

  def image_presence
    errors.add(:image, "を選択してください") unless image.attached?
  end

  def image_content_type
    return unless image.attached?

    content_type = image.blob.content_type.to_s
    return if ALLOWED_CONTENT_TYPES.include?(content_type)

    errors.add(:image, "は jpg / png / webp / heic のみアップロードできます")
  end
end
