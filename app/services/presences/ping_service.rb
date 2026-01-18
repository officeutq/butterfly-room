# frozen_string_literal: true

module Presences
  class PingService
    def initialize(stream_session:, customer_user:)
      @stream_session = stream_session
      @customer_user = customer_user
    end

    def call!
      now = Time.current

      ::Presence.transaction do
        latest_active = ::Presence
          .where(stream_session_id: @stream_session.id, customer_user_id: @customer_user.id, left_at: nil)
          .order(joined_at: :desc, id: :desc)
          .lock("FOR UPDATE")
          .first

        if latest_active
          latest_active.update!(last_seen_at: now)
        else
          ::Presence.create!(
            stream_session_id: @stream_session.id,
            customer_user_id: @customer_user.id,
            joined_at: now,
            last_seen_at: now,
            left_at: nil
          )
        end
      end
    end
  end
end
