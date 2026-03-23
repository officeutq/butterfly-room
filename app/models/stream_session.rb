class StreamSession < ApplicationRecord
  belongs_to :booth
  belongs_to :store
  belongs_to :started_by_cast_user, class_name: "User"
  has_many :presences, dependent: :destroy

  enum :status, { live: 0, ended: 1 }

  validates :title, length: { maximum: 64 }, allow_nil: true

  delegate :current_stream_session_id, :status, to: :booth, prefix: true
end
