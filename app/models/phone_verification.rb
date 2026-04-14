# frozen_string_literal: true

class PhoneVerification < ApplicationRecord
  PURPOSE_LOGIN = "login"
  PURPOSE_VERIFY_PHONE = "verify_phone".freeze

  PURPOSES = [
    PURPOSE_LOGIN,
    PURPOSE_VERIFY_PHONE
  ].freeze

  belongs_to :user, optional: true

  validates :phone_number, presence: true
  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :otp_code_digest, presence: true
  validates :expires_at, presence: true
  validates :last_sent_at, presence: true
  validates :attempts_count, numericality: { greater_than_or_equal_to: 0 }

  scope :for_phone_and_purpose, ->(phone_number, purpose) { where(phone_number:, purpose:) }
  scope :active, -> { where(verified_at: nil, consumed_at: nil, invalidated_at: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def active?
    verified_at.nil? && consumed_at.nil? && invalidated_at.nil?
  end

  def expired?
    expires_at <= Time.current
  end

  def attempts_exceeded?(max_attempts:)
    attempts_count >= max_attempts
  end
end
