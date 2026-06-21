# frozen_string_literal: true

class NotificationRead < ApplicationRecord
  belongs_to :notification
  belongs_to :user

  validates :notification_id, presence: true
  validates :user_id, presence: true
  validates :read_at, presence: true
end
