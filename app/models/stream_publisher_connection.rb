class StreamPublisherConnection < ApplicationRecord
  DISCONNECT_REASONS = %w[cancel replace end].freeze

  belongs_to :stream_session
  belongs_to :booth
  belongs_to :user

  validates :request_id, :ivs_stage_arn, presence: true
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :disconnect_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :disconnect_reason, inclusion: { in: DISCONNECT_REASONS }, allow_nil: true
  validate :booth_matches_stream_session
  validate :participant_token_is_complete
  validate :disconnect_request_is_complete

  scope :unreleased, -> { where(released_at: nil) }
  scope :disconnect_pending, -> { where.not(disconnect_requested_at: nil).where(disconnected_at: nil) }

  before_destroy :preserve_connection_history

  private

  def booth_matches_stream_session
    if stream_session && booth_id != stream_session.booth_id
      errors.add(:booth, :invalid)
    end
  end

  def participant_token_is_complete
    unless ivs_participant_id.nil? == token_expires_at.nil?
      errors.add(:ivs_participant_id, :invalid)
    end
  end

  def disconnect_request_is_complete
    unless disconnect_requested_at.nil? == disconnect_reason.nil?
      errors.add(:disconnect_reason, :invalid)
    end
  end

  def preserve_connection_history
    errors.add(:base, "配信接続の履歴は削除できません")
    throw :abort
  end
end
