class StoreMembership < ApplicationRecord
  enum :membership_role, { cast: 0, admin: 1 }
end
