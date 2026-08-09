# frozen_string_literal: true

module LpAnalytics
  module Completions
    class RecordService
      Result = Data.define(:event, :duplicate, :error)

      def initialize(visit:, event_type:, completion_record:, now: Time.current, logger: Rails.logger)
        @visit = visit
        @event_type = event_type.to_s.strip
        @completion_record = completion_record
        @now = now
        @logger = logger
      end

      def call
        validate_input!
        duplicate_event = find_duplicate_event
        if duplicate_event
          return Result.new(event: duplicate_event, duplicate: true, error: nil)
        end

        event = record_event!

        Result.new(event: event, duplicate: false, error: nil)
      rescue ActiveRecord::RecordNotUnique => error
        duplicate_event = find_duplicate_event
        unless duplicate_event
          log_failure(error)
          return Result.new(event: nil, duplicate: false, error: error)
        end

        Result.new(event: duplicate_event, duplicate: true, error: nil)
      rescue StandardError => error
        log_failure(error)
        Result.new(event: nil, duplicate: false, error: error)
      end

      private

      def validate_input!
        expected_type = Event::COMPLETION_EVENT_RECORD_TYPES[@event_type]
        raise ArgumentError unless @visit.is_a?(Visit) && @visit.persisted?
        raise ArgumentError unless expected_type == completion_record_type
        raise ArgumentError unless @completion_record.persisted?
        raise ArgumentError unless @completion_record.lp_analytics_visit_id == @visit.id
      end

      def record_event!
        event = Event.new(
          visit: @visit,
          event_type: @event_type,
          lp_identifier: @visit.lp_identifier,
          occurred_at: @now,
          completion_record: @completion_record,
          metadata: {}
        )

        Event.transaction(requires_new: true) do
          event.save!
          touch_visit_activity!
        end

        event
      end

      def find_duplicate_event
        event = Event.find_by(
          completion_record_type: completion_record_type,
          completion_record_id: @completion_record.id
        )
        return if event.blank?
        return unless event.lp_analytics_visit_id == @visit.id && event.event_type == @event_type

        event
      end

      def completion_record_type
        @completion_record.class.base_class.name
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

      def log_failure(error)
        @logger.error(
          {
            event: "lp_analytics_completion_record_failed",
            event_type: @event_type,
            lp_analytics_visit_id: @visit&.id,
            completion_record_type: completion_record_type,
            completion_record_id: @completion_record&.id,
            error_class: error.class.name
          }.to_json
        )
      rescue StandardError
        @logger.error("[lp_analytics] completion record failed")
      end
    end
  end
end
