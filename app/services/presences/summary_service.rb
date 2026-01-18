# frozen_string_literal: true

module Presences
  class SummaryService
    def initialize(stream_session:, threshold_seconds: 45)
      @stream_session = stream_session
      @threshold_seconds = threshold_seconds
    end

    def call!
      ::Presence
        .where(stream_session_id: @stream_session.id, left_at: nil)
        .where("last_seen_at >= ?", Time.current - @threshold_seconds)
        .distinct
        .count(:customer_user_id)
    end
  end
end
