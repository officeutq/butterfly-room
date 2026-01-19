# frozen_string_literal: true

class DrinkOrderNotifier
  def self.replace_pending_list(drink_order)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ drink_order.stream_session, :pending_drink_orders ],
      target: "cast_pending_drink_orders",
      partial: "cast/stream_sessions/pending_drink_orders",
      locals: { stream_session: drink_order.stream_session }
    )
  end
end
