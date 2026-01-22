# frozen_string_literal: true

class StoreLedgerEntry < ApplicationRecord
  belongs_to :store
  belongs_to :stream_session
  belongs_to :drink_order

  validates :points, numericality: { greater_than: 0 }
  validates :occurred_at, presence: true
end
