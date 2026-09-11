# frozen_string_literal: true

module LogEntry
  extend ActiveSupport::Concern

  SOURCES = %w[application web job runner ivs].freeze

  included do
    belongs_to :actor_user, class_name: "User", optional: true
    scope :active, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }

    validates :occurred_at, presence: true
    validates :source, inclusion: { in: SOURCES }
    validates :request_id, length: { maximum: 100 }, allow_nil: true
    validates :actor_user_id, :store_id, :stream_session_id,
      numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  end

  # ArchiveService alone changes archived_at through a bounded update_all.
  def readonly?
    persisted? || super
  end
end
