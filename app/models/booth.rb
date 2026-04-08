class Booth < ApplicationRecord
  include NormalizedImageAttachment

  belongs_to :store
  belongs_to :current_stream_session, class_name: "StreamSession", optional: true

  has_many :stream_sessions, dependent: :restrict_with_error
  has_many :booth_casts, dependent: :restrict_with_error
  has_many :cast_users, through: :booth_casts, source: :cast_user
  has_many :favorite_booths, dependent: :destroy
  has_one_attached :thumbnail_image

  enum :status, { offline: 0, live: 1, away: 2, standby: 3 }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def primary_cast_user_id
    booth_casts.order(created_at: :desc, id: :desc).pick(:cast_user_id)
  end

  def primary_cast_user
    if booth_casts.loaded?
      booth_casts.max_by { |booth_cast| [ booth_cast.created_at, booth_cast.id ] }&.cast_user
    else
      booth_casts.includes(:cast_user).order(created_at: :desc, id: :desc).first&.cast_user
    end
  end
end
