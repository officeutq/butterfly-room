class DrinkOrder < ApplicationRecord
  enum :status, { pending: 0, consumed: 1, refunded: 2 }
end
