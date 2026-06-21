# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"

  has_many :notification_taggings, dependent: :destroy
  has_many :notification_tags, through: :notification_taggings
  has_many :notification_reads, dependent: :destroy

  validates :title, presence: true
  validates :body, presence: true
  validates :published_at, presence: true
  validates :enabled, inclusion: { in: [ true, false ] }

  scope :published, -> {
    where(enabled: true)
      .where("published_at <= ?", Time.current)
      .order(published_at: :desc)
  }
end
