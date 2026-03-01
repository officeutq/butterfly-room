# frozen_string_literal: true

class SettlementEvent < ApplicationRecord
  belongs_to :settlement
  belongs_to :actor_user, class_name: "User"

  enum :action, {
    created: 0,
    confirmed: 1,
    exported: 2,
    marked_paid: 3,
    export_failed: 10
  }

  validates :action, presence: true
end
