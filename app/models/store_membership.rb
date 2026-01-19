class StoreMembership < ApplicationRecord
  belongs_to :store
  belongs_to :user

  enum :membership_role, { cast: 0, admin: 1 }

  scope :admin_only, -> { where(membership_role: membership_roles[:admin]) }
end
