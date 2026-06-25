# frozen_string_literal: true

class SupportInquiry < ApplicationRecord
  SUBJECT_MAX_LENGTH = 120

  belongs_to :user
  belongs_to :store, optional: true
  belongs_to :source_comment, class_name: "Comment", optional: true

  has_many :support_inquiry_messages, dependent: :destroy

  enum :category, {
    bug: 0,
    request: 1,
    question: 2,
    report: 3,
    other: 4
  }

  enum :status, {
    not_started: 0,
    in_progress: 1,
    resolved: 2
  }

  enum :last_message_sender_kind, {
    user: 0,
    system_admin: 1
  }, prefix: :last_message_sender

  validates :category, presence: true
  validates :status, presence: true
  validates :subject, presence: true, length: { maximum: SUBJECT_MAX_LENGTH }
  validates :reply_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name_snapshot, presence: true
  validates :role_snapshot, presence: true
  validates :last_message_at, presence: true
  validates :last_message_sender_kind, presence: true
end
