class StoreBan < ApplicationRecord
  belongs_to :store
  belongs_to :customer_user, class_name: "User"
  belongs_to :created_by_store_admin_user, class_name: "User"
end
