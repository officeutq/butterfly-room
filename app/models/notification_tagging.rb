# frozen_string_literal: true

class NotificationTagging < ApplicationRecord
  belongs_to :notification
  belongs_to :notification_tag

  validates :notification_id, presence: true
  validates :notification_tag_id, presence: true
end
