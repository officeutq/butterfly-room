class WalletTransaction < ApplicationRecord
  belongs_to :wallet
  belongs_to :ref, polymorphic: true, optional: true

  enum :kind, { purchase: 0, hold: 1, release: 2, consume: 3, adjustment: 4 }
end
