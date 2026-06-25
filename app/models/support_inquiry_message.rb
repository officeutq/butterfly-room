# frozen_string_literal: true

class SupportInquiryMessage < ApplicationRecord
  BODY_MAX_LENGTH = 5_000

  belongs_to :support_inquiry
  belongs_to :sender_user, class_name: "User"

  enum :sender_kind, {
    user: 0,
    system_admin: 1
  }, prefix: :sender

  validates :sender_kind, presence: true
  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }
end
