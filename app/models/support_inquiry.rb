# frozen_string_literal: true

class SupportInquiry < ApplicationRecord
  SUBJECT_MAX_LENGTH = 120
  CATEGORY_LABELS = {
    bug: "バグ",
    request: "要望",
    question: "質問",
    report: "通報・運営報告",
    other: "その他"
  }.freeze
  STATUS_LABELS = {
    not_started: "未着手",
    in_progress: "進行中",
    resolved: "解決"
  }.freeze
  SENDER_KIND_LABELS = {
    user: "ユーザー",
    system_admin: "運営"
  }.freeze

  belongs_to :user
  belongs_to :store, optional: true
  belongs_to :source_comment, class_name: "Comment", optional: true

  has_many :support_inquiry_messages,
    -> { order(:created_at, :id) },
    dependent: :destroy,
    inverse_of: :support_inquiry

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

  def self.category_select_options
    categories.keys.map { |key| [ CATEGORY_LABELS.fetch(key.to_sym), key ] }
  end

  def category_label
    CATEGORY_LABELS[category&.to_sym] || category.to_s
  end

  def status_label
    STATUS_LABELS[status&.to_sym] || status.to_s
  end

  def last_message_sender_kind_label
    SENDER_KIND_LABELS[last_message_sender_kind&.to_sym] || last_message_sender_kind.to_s
  end
end
