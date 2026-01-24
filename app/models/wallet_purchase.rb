class WalletPurchase < ApplicationRecord
  belongs_to :wallet

  enum :status, {
    pending: 0,
    paid: 1,
    credited: 2,
    canceled: 3,
    failed: 4
  }

  validates :points, numericality: { only_integer: true, greater_than: 0 }
end
