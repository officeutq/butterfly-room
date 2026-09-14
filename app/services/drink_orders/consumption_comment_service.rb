module DrinkOrders
  class ConsumptionCommentService
    def initialize(drink_order:)
      @drink_order = drink_order
    end

    def call!
      @drink_order.with_lock do
        raise ConsumeService::InvalidStatusError unless @drink_order.consumed?

        # 旧通知はmetadataだけに注文IDを持つ。論理削除済みも再作成しない。
        existing = Comment.find_by(drink_order_id: @drink_order.id) ||
          Comment.where(stream_session_id: @drink_order.stream_session_id, kind: Comment::KIND_DRINK_CONSUMED)
            .where("metadata ->> 'drink_order_id' = ?", @drink_order.id.to_s).order(:id).first
        return existing if existing

        publisher = @drink_order.stream_session.actual_publisher_user
        Comment.create!(
          stream_session: @drink_order.stream_session, booth_id: @drink_order.booth_id,
          user: publisher, kind: Comment::KIND_DRINK_CONSUMED, drink_order: @drink_order,
          metadata: { drink_item_id: @drink_order.drink_item_id, drink_order_id: @drink_order.id,
                      publisher_unknown: publisher.nil? }
        )
      end
    end
  end
end
