class StreamSession < ApplicationRecord
  ACTUAL_PUBLISHER_SOURCES = %w[ivs_verified legacy_creator_backfill evidence_backfill].freeze

  belongs_to :booth
  belongs_to :store
  belongs_to :started_by_cast_user, class_name: "User"
  belongs_to :actual_publisher_user, class_name: "User", optional: true
  belongs_to :current_publisher_connection, class_name: "StreamPublisherConnection", optional: true
  has_many :stream_publisher_connections, dependent: :restrict_with_error
  has_many :presences, dependent: :destroy
  has_many :comments, dependent: :destroy

  enum :status, { live: 0, ended: 1 }

  validates :title, length: { maximum: 64 }, allow_nil: true
  validates :actual_publisher_source, inclusion: { in: ACTUAL_PUBLISHER_SOURCES }, allow_nil: true
  validates :publisher_generation, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :actual_publisher_record_is_complete
  validate :current_publisher_connection_belongs_to_session

  scope :in_published_stores, -> { joins(:store).merge(Store.published) }
  scope :actually_broadcasting_by, ->(user) {
    if user&.id
      joins(:booth).where(actual_publisher_user_id: user.id, status: :live, ended_at: nil)
        .where.not(broadcast_started_at: nil)
        .where(booths: { status: %i[live away] })
        .where("booths.current_stream_session_id = stream_sessions.id")
    else
      none
    end
  }

  delegate :current_stream_session_id, :status, to: :booth, prefix: true

  def actual_publisher?(user)
    user&.id.present? && actual_publisher_user_id.present? && actual_publisher_user_id == user.id
  end

  def publisher_recording_state
    if ended?
      return :inconsistent if ended_at.nil? || (broadcast_started_at && ended_at < broadcast_started_at)
      return :recorded if complete_actual_publisher_record?
      return :unknown if empty_actual_publisher_record?
    elsif live? && ended_at.nil? && id.present? && booth&.current_stream_session_id == id
      return :not_started if booth.standby? && broadcast_started_at.nil? && empty_actual_publisher_record?
      return :recorded if (booth.live? || booth.away?) && complete_actual_publisher_record?
    end

    :inconsistent
  end

  def broadcast_duration_seconds
    return 0 if broadcast_started_at.blank?
    return 0 if ended_at.blank?
    return 0 if ended_at < broadcast_started_at

    (ended_at - broadcast_started_at).to_i
  end

  private

  def empty_actual_publisher_record?
    actual_publisher_user_id.nil? && actual_publisher_source.nil? && actual_publisher_recorded_at.nil?
  end

  def complete_actual_publisher_record?
    actual_publisher_user_id.present? && ACTUAL_PUBLISHER_SOURCES.include?(actual_publisher_source) &&
      actual_publisher_recorded_at.present? && broadcast_started_at.present?
  end

  def actual_publisher_record_is_complete
    unless empty_actual_publisher_record? || complete_actual_publisher_record?
      errors.add(:actual_publisher_user, :invalid)
    end
    errors.add(:actual_publisher_evidence, :invalid) unless actual_publisher_evidence.is_a?(Hash)
  end

  def current_publisher_connection_belongs_to_session
    if current_publisher_connection && (id.nil? || current_publisher_connection.stream_session_id != id)
      errors.add(:current_publisher_connection, :invalid)
    end
  end
end
