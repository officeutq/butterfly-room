class Booth < ApplicationRecord
  belongs_to :store
  belongs_to :current_stream_session, class_name: "StreamSession", optional: true

  has_many :stream_sessions, dependent: :restrict_with_error

  enum :status, { offline: 0, live: 1, away: 2 }
end
