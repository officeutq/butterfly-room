class StreamPublishAttempt < ApplicationRecord
  belongs_to :stream_session
  belongs_to :user

  scope :open, -> { where(retired_at: nil) }

  validates :request_id, presence: true, format: { with: /\A[0-9a-f-]{36}\z/i }

  def usable?
    retired_at.nil? && cancelled_at.nil? && participant_id.present?
  end
end
