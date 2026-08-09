# frozen_string_literal: true

require "digest"

module LpAnalytics
  class Event < ApplicationRecord
    self.table_name = "lp_analytics_events"

    EVENT_TYPES = %w[
      lp_view
      scroll_reached
      section_reached
      cta_reached
      cta_clicked
      faq_opened
      store_registration_form_view
      store_registration_complete
      store_contact_form_view
      store_contact_complete
    ].freeze
    DEDUPLICATED_EVENT_TYPES = %w[scroll_reached section_reached cta_reached].freeze
    COMPLETION_EVENT_RECORD_TYPES = {
      "store_registration_complete" => "Store",
      "store_contact_complete" => "StoreContactSubmission"
    }.freeze
    BROWSER_EVENT_TYPES = (EVENT_TYPES - COMPLETION_EVENT_RECORD_TYPES.keys).freeze
    UUID_PATTERN = Visit::UUID_PATTERN

    belongs_to :visit,
      class_name: "LpAnalytics::Visit",
      foreign_key: :lp_analytics_visit_id,
      inverse_of: :events
    belongs_to :completion_record, polymorphic: true, optional: true

    before_validation :normalize_fields

    validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
    validates :event_value, length: { maximum: 100 }, allow_nil: true
    validates :lp_identifier, presence: true, length: { maximum: 100 }
    validates :occurred_at, presence: true
    validates :browser_event_id,
      format: { with: UUID_PATTERN },
      allow_nil: true
    validates :dedupe_key, length: { is: 64 }, allow_nil: true
    validates :completion_record_id,
      uniqueness: { scope: :completion_record_type },
      allow_nil: true
    validate :lp_identifier_matches_visit
    validate :event_value_is_allowed
    validate :dedupe_key_is_valid
    validate :metadata_is_allowed
    validate :completion_record_is_valid

    def self.dedupe_key_for(event_type, event_value)
      return unless DEDUPLICATED_EVENT_TYPES.include?(event_type)

      Digest::SHA256.hexdigest([ event_type, event_value ].join("\0"))
    end

    private

    def normalize_fields
      self.event_type = event_type.to_s.strip.presence
      self.event_value = event_value.to_s.strip.presence
      self.lp_identifier = lp_identifier.to_s.strip.presence
      self.browser_event_id = browser_event_id.to_s.strip.downcase.presence
      self.dedupe_key = dedupe_key.to_s.strip.presence
    end

    def lp_identifier_matches_visit
      return if visit.blank? || lp_identifier == visit.lp_identifier

      errors.add(:lp_identifier, :invalid)
    end

    def event_value_is_allowed
      return if event_type.blank? || lp_identifier.blank?
      return if Configuration.allowed_event_value?(
        lp_identifier: lp_identifier,
        event_type: event_type,
        event_value: event_value
      )

      errors.add(:event_value, :inclusion)
    end

    def dedupe_key_is_valid
      expected_key = self.class.dedupe_key_for(event_type, event_value)
      return if dedupe_key == expected_key

      errors.add(:dedupe_key, :invalid)
    end

    def metadata_is_allowed
      return if Configuration.valid_metadata?(metadata)

      errors.add(:metadata, :invalid)
    end

    def completion_record_is_valid
      expected_type = COMPLETION_EVENT_RECORD_TYPES[event_type]
      if expected_type.nil?
        return if completion_record_type.blank? && completion_record_id.blank?

        errors.add(:completion_record, :invalid)
        return
      end

      unless completion_record_type == expected_type && completion_record_id.present?
        errors.add(:completion_record, :invalid)
        return
      end

      record = completion_record
      return if record.present? && record.lp_analytics_visit_id == lp_analytics_visit_id

      errors.add(:completion_record, :invalid)
    end
  end
end
