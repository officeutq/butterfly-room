# frozen_string_literal: true

module LpAnalytics
  class Visit < ApplicationRecord
    self.table_name = "lp_analytics_visits"

    LP_IDENTIFIER_MAX_LENGTH = 100
    TRAFFIC_VALUE_MAX_LENGTH = 100
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    DEVICE_TYPES = %w[pc smartphone tablet].freeze
    BROWSER_TYPES = %w[edge firefox chrome safari other].freeze

    has_many :events,
      class_name: "LpAnalytics::Event",
      foreign_key: :lp_analytics_visit_id,
      inverse_of: :visit,
      dependent: :restrict_with_error

    before_validation :assign_public_id, on: :create

    validates :public_id,
      presence: true,
      format: { with: UUID_PATTERN },
      uniqueness: true
    validates :lp_identifier,
      presence: true,
      length: { maximum: LP_IDENTIFIER_MAX_LENGTH }
    validates :traffic_source,
      :utm_source,
      :utm_medium,
      :utm_campaign,
      :utm_content,
      :referral_code,
      length: { maximum: TRAFFIC_VALUE_MAX_LENGTH },
      allow_nil: true
    validates :device_type, presence: true, inclusion: { in: DEVICE_TYPES }
    validates :browser_type, inclusion: { in: BROWSER_TYPES }, allow_nil: true
    validates :started_at, :last_activity_at, presence: true
    validate :last_activity_is_not_before_start

    def traffic_attributes
      {
        traffic_source: traffic_source,
        utm_source: utm_source,
        utm_medium: utm_medium,
        utm_campaign: utm_campaign,
        utm_content: utm_content,
        referral_code: referral_code
      }
    end

    def self.find_by_public_id(public_id)
      normalized_public_id = public_id.to_s.strip
      return unless UUID_PATTERN.match?(normalized_public_id)

      find_by(public_id: normalized_public_id)
    end

    private

    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end

    def last_activity_is_not_before_start
      return if started_at.blank? || last_activity_at.blank?
      return unless last_activity_at < started_at

      errors.add(:last_activity_at, :invalid)
    end
  end
end
