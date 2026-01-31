class Booth < ApplicationRecord
  belongs_to :store
  belongs_to :current_stream_session, class_name: "StreamSession", optional: true

  has_many :stream_sessions, dependent: :restrict_with_error
  has_many :booth_casts, dependent: :restrict_with_error
  has_many :cast_users, through: :booth_casts, source: :cast_user

  enum :status, { offline: 0, live: 1, away: 2 }

  def primary_cast_user_id
    booth_casts.order(created_at: :desc, id: :desc).pick(:cast_user_id)
  end
end
