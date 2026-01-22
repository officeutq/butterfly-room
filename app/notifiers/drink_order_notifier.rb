# frozen_string_literal: true

class DrinkOrderNotifier
  def self.replace_pending_lists(drink_order)
    stream_session = drink_order.stream_session

    # customer/public
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :pending_drink_orders ],
      target: "pending_drink_orders",
      partial: "stream_sessions/pending_drink_orders",
      locals: { stream_session: stream_session }
    )

    # cast
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :cast_pending_drink_orders ],
      target: "cast_pending_drink_orders",
      partial: "cast/stream_sessions/pending_drink_orders",
      locals: { stream_session: stream_session }
    )
  end
end
