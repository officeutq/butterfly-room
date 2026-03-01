# frozen_string_literal: true

require "digest"
require "securerandom"

class StoreAdminInvitation < ApplicationRecord
  belongs_to :store
  belongs_to :invited_by_user, class_name: "User"
  belongs_to :accepted_by_user, class_name: "User", optional: true

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  def usable?
    !used? && !expired?
  end

  def status_label
    return "使用済み" if used?
    return "期限切れ" if expired?
    "有効"
  end

  # --- token digest helpers ---

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.digest_for(token)
    secret = Rails.application.secret_key_base
    Digest::SHA256.hexdigest("#{secret}--#{token}")
  end

  def self.find_by_token(token)
    find_by(token_digest: digest_for(token))
  end
end
