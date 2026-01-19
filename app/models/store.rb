# frozen_string_literal: true

class Store < ApplicationRecord
  has_many :booths, dependent: :destroy
  has_many :store_memberships, dependent: :destroy
  has_many :drink_items, dependent: :destroy
end
