class Booth < ApplicationRecord
  enum :status, { offline: 0, live: 1, away: 2 }
end
