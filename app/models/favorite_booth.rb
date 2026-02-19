class FavoriteBooth < ApplicationRecord
  belongs_to :user
  belongs_to :booth

  validates :user_id, presence: true
  validates :booth_id, presence: true
end
