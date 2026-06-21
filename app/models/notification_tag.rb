# frozen_string_literal: true

class NotificationTag < ApplicationRecord
  has_many :notification_taggings, dependent: :destroy
  has_many :notifications, through: :notification_taggings

  validates :name, presence: true, uniqueness: true
end
