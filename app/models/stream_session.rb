class StreamSession < ApplicationRecord
  belongs_to :booth
  belongs_to :store
  belongs_to :started_by_cast_user, class_name: "User"
  belongs_to :broadcast_started_by_user, class_name: "User", optional: true
  has_many :stream_publish_attempts, dependent: :restrict_with_error
  has_many :presences, dependent: :destroy
  has_many :comments, dependent: :destroy

  enum :status, { live: 0, ended: 1 }

  validates :title, length: { maximum: 64 }, allow_nil: true
  validates :broadcast_identity_source, inclusion: { in: %w[ivs_confirmed legacy_creator_backfill evidence] }, allow_nil: true

  scope :in_published_stores, -> { joins(:store).merge(Store.published) }

  delegate :current_stream_session_id, :status, to: :booth, prefix: true

  def broadcaster?(user)
    user.present? && broadcast_started_by_user_id.present? && broadcast_started_by_user_id == user.id
  end

  def broadcaster_label
    return broadcast_started_by_user.display_name if broadcast_started_by_user.present?

    broadcast_started_at.present? || publisher_protocol.nil? ? "配信者不明" : "配信未開始"
  end

  def broadcast_duration_seconds
    return 0 if broadcast_started_at.blank?
    return 0 if ended_at.blank?
    return 0 if ended_at < broadcast_started_at

    (ended_at - broadcast_started_at).to_i
  end
end
