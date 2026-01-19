class Wallet < ApplicationRecord
  belongs_to :customer_user, class_name: "User"
  has_many :wallet_transactions, dependent: :destroy

  validates :available_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reserved_points,  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
