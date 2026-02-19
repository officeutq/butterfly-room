# frozen_string_literal: true

class Store < ApplicationRecord
  belongs_to :referral_code, optional: true

  has_many :booths, dependent: :destroy
  has_many :store_memberships, dependent: :destroy
  has_many :drink_items, dependent: :destroy
  has_many :store_bans, dependent: :destroy
  has_many :favorite_stores, dependent: :destroy
end
