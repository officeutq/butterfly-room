# frozen_string_literal: true

module LpAnalytics
  module Events
    class RecordService
      class InvalidEventError < StandardError; end

      Result = Data.define(:event, :duplicate)

      def initialize(
        visit:,
        event_type:,
        event_value: nil,
        browser_event_id: nil,
        metadata: {},
        occurred_at: nil,
        now: Time.current
      )
        @visit = visit
        @event_type = normalize_event_type(event_type)
        @event_value = normalize_event_value(event_value)
        @browser_event_id = normalize_browser_event_id(browser_event_id)
        @metadata = normalize_metadata(metadata)
        @occurred_at = occurred_at || now
        @now = now
      end

      def call
        validate_input!
        event = build_event

        Event.transaction(requires_new: true) do
          event.save!
          touch_visit_activity!
        end

        Result.new(event: event, duplicate: false)
      rescue ActiveRecord::RecordNotUnique
        duplicate_event = find_duplicate_event
        raise unless duplicate_event

        touch_visit_activity! if duplicate_event.lp_analytics_visit_id == @visit.id
        Result.new(event: duplicate_event, duplicate: true)
      end

      private

      def normalize_event_type(value)
        value.is_a?(String) ? value.strip : nil
      end

      def normalize_event_value(value)
        @event_value_input_valid = value.nil? || value.is_a?(String) || value.is_a?(Integer)
        return unless @event_value_input_valid

        value.to_s.strip.presence
      end

      def normalize_browser_event_id(value)
        @browser_event_id_input_valid = value.nil? || (value.is_a?(String) && value.strip.present?)
        return unless @browser_event_id_input_valid

        value&.strip&.downcase
      end

      def normalize_metadata(value)
        source =
          case value
          when ActionController::Parameters
            value.to_unsafe_h
          when Hash
            value
          else
            nil
          end

        return nil unless source

        source.to_h.transform_keys(&:to_s)
      rescue TypeError, NoMethodError
        nil
      end

      def validate_input!
        raise InvalidEventError unless @visit.is_a?(Visit) && @visit.persisted?
        raise InvalidEventError unless @event_value_input_valid
        raise InvalidEventError unless @browser_event_id_input_valid
        raise InvalidEventError unless Event::BROWSER_EVENT_TYPES.include?(@event_type)
        raise InvalidEventError unless Configuration.allowed_event_value?(
          lp_identifier: @visit.lp_identifier,
          event_type: @event_type,
          event_value: @event_value
        )
        raise InvalidEventError unless Configuration.valid_metadata?(@metadata)
        raise InvalidEventError unless valid_browser_event_id?
        raise InvalidEventError unless @occurred_at.respond_to?(:acts_like_time?) && @occurred_at.acts_like_time?
      end

      def valid_browser_event_id?
        @browser_event_id.nil? || Event::UUID_PATTERN.match?(@browser_event_id)
      end

      def build_event
        Event.new(
          visit: @visit,
          event_type: @event_type,
          event_value: @event_value,
          lp_identifier: @visit.lp_identifier,
          occurred_at: @occurred_at,
          browser_event_id: @browser_event_id,
          dedupe_key: Event.dedupe_key_for(@event_type, @event_value),
          metadata: @metadata
        )
      end

      def find_duplicate_event
        if @browser_event_id
          duplicate = Event.find_by(browser_event_id: @browser_event_id)
          return duplicate if duplicate
        end

        dedupe_key = Event.dedupe_key_for(@event_type, @event_value)
        return if dedupe_key.nil?

        Event.find_by(lp_analytics_visit_id: @visit.id, dedupe_key: dedupe_key)
      end

      def touch_visit_activity!
        Visit.where(id: @visit.id).update_all(
          [
            "last_activity_at = GREATEST(last_activity_at, ?), updated_at = GREATEST(updated_at, ?)",
            @now,
            @now
          ]
        )
        @visit.last_activity_at = [ @visit.last_activity_at, @now ].compact.max
      end
    end
  end
end
