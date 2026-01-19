class DrinkOrder < ApplicationRecord
  belongs_to :store
  belongs_to :booth
  belongs_to :stream_session
  belongs_to :customer_user, class_name: "User"
  belongs_to :drink_item

  enum :status, { pending: 0, consumed: 1, refunded: 2 }
end
