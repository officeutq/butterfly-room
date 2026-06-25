# frozen_string_literal: true

class SupportInquiryMessage < ApplicationRecord
  BODY_MAX_LENGTH = 5_000
  SENDER_KIND_LABELS = {
    user: "ユーザー",
    system_admin: "運営"
  }.freeze

  belongs_to :support_inquiry, inverse_of: :support_inquiry_messages
  belongs_to :sender_user, class_name: "User"

  enum :sender_kind, {
    user: 0,
    system_admin: 1
  }, prefix: :sender

  validates :sender_kind, presence: true
  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }

  def sender_kind_label
    SENDER_KIND_LABELS[sender_kind&.to_sym] || sender_kind.to_s
  end
end
