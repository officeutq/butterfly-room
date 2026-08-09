# frozen_string_literal: true

module LpAnalytics
  class VisitDetailQuery
    Result = Data.define(:visit, :events, :final_reach_event, :final_result_event)

    REACH_EVENT_TYPES = %w[scroll_reached section_reached cta_reached].freeze
    RESULT_EVENT_TYPE_GROUPS = [
      %w[store_registration_complete store_contact_complete].freeze,
      %w[store_registration_form_view store_contact_form_view].freeze,
      %w[cta_clicked].freeze
    ].freeze

    def initialize(public_id:)
      @public_id = public_id
    end

    def call
      visit = Visit.find_by_public_id(public_id)
      raise ActiveRecord::RecordNotFound, "LpAnalytics::Visit not found" unless visit

      events = visit.events.order(:occurred_at, :id).to_a
      Result.new(
        visit: visit,
        events: events,
        final_reach_event: events.reverse.find { |event| REACH_EVENT_TYPES.include?(event.event_type) },
        final_result_event: final_result_event(events)
      )
    end

    private

    attr_reader :public_id

    def final_result_event(events)
      RESULT_EVENT_TYPE_GROUPS.each do |event_types|
        event = events.reverse.find { |candidate| event_types.include?(candidate.event_type) }
        return event if event
      end

      nil
    end
  end
end
