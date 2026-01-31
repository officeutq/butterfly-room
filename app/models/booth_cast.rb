class BoothCast < ApplicationRecord
  belongs_to :booth
  belongs_to :cast_user, class_name: "User"

  validates :booth_id, presence: true
  validates :cast_user_id, presence: true
end
