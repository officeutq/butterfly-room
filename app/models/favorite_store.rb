class FavoriteStore < ApplicationRecord
  belongs_to :user
  belongs_to :store

  validates :user_id, presence: true
  validates :store_id, presence: true
end
