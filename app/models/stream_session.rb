class StreamSession < ApplicationRecord
  enum :status, { live: 0, ended: 1 }
end
