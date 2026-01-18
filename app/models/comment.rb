class Comment < ApplicationRecord
  belongs_to :stream_session
  belongs_to :booth
  belongs_to :user

  scope :alive, -> { where(deleted_at: nil) }

  validates :body, presence: true, length: { maximum: 200 }
end
