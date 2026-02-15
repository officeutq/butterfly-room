# frozen_string_literal: true

class ReferralCode < ApplicationRecord
  has_many :stores, dependent: :nullify

  validates :code, presence: true, uniqueness: true

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # 店舗登録で「使用可能」かどうか（#137側で利用する想定）
  def usable?
    enabled? && !expired?
  end
end
