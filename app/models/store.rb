# frozen_string_literal: true

class Store < ApplicationRecord
  belongs_to :referral_code, optional: true

  has_many :booths, dependent: :destroy
  has_many :store_memberships, dependent: :destroy
  has_many :drink_items, dependent: :destroy
  has_many :store_bans, dependent: :destroy
  has_many :favorite_stores, dependent: :destroy

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

  validate :thumbnail_validation

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

  private

  def thumbnail_validation
    return unless thumbnail.attached?

    # content_type
    allowed = %w[image/png image/jpeg image/webp]
    if thumbnail.blob.content_type.blank? || !allowed.include?(thumbnail.blob.content_type)
      errors.add(:thumbnail, "は png / jpg / webp のみアップロードできます")
    end

    # size（5MB）
    if thumbnail.blob.byte_size > 5.megabytes
      errors.add(:thumbnail, "は 5MB 以下にしてください")
    end
  end
end
