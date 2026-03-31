# frozen_string_literal: true

class CommentReport < ApplicationRecord
  belongs_to :comment
  belongs_to :reporter_user, class_name: "User"
  belongs_to :reported_user, class_name: "User"
  belongs_to :store
  belongs_to :booth
  belongs_to :stream_session

  enum :status, { pending: 0, resolved: 1, rejected: 2 }

  validates :comment_id, uniqueness: { scope: :reporter_user_id }
end
