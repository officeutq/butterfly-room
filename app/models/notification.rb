# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"
  belongs_to :recipient_user, class_name: "User", optional: true

  has_many :notification_taggings, dependent: :destroy
  has_many :notification_tags, through: :notification_taggings
  has_many :notification_reads, dependent: :destroy

  validates :title, presence: true
  validates :body, presence: true
  validates :published_at, presence: true
  validates :enabled, inclusion: { in: [ true, false ] }
  validate :link_path_is_relative_path

  scope :published, -> {
    where(enabled: true)
      .where("published_at <= ?", Time.current)
      .order(published_at: :desc)
  }

  scope :visible_to, ->(user) {
    relation = published
    if user.present?
      relation.where(recipient_user_id: [ nil, user.id ])
    else
      relation.where(recipient_user_id: nil)
    end
  }

  def unread_for?(user)
    return false if user.blank?

    !notification_reads.exists?(user_id: user.id)
  end

  private

  def link_path_is_relative_path
    value = link_path.to_s
    return if value.blank?

    if value.start_with?("/") &&
        !value.start_with?("//") &&
        !value.include?("\n") &&
        !value.include?("\r") &&
        !value.include?("\0")
      return
    end

    errors.add(:link_path, "は相対パスで指定してください")
  end
end
