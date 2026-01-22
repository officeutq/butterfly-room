# frozen_string_literal: true

module DrinkOrders
  class FifoGuard
    def initialize(stream_session_id:)
      @stream_session_id = stream_session_id
    end

    def lock_head_pending!
      DrinkOrder
        .where(stream_session_id: @stream_session_id, status: :pending)
        .order(:created_at, :id)
        .lock
        .first
    end
  end
end
