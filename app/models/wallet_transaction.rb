class WalletTransaction < ApplicationRecord
  enum :kind, { purchase: 0, hold: 1, release: 2, consume: 3, adjustment: 4 }
end
