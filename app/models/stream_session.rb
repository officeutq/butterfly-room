class StreamSession < ApplicationRecord
  belongs_to :booth
  belongs_to :store
  belongs_to :started_by_cast_user, class_name: "User"

  enum :status, { live: 0, ended: 1 }
end
