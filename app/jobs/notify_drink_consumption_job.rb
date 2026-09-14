class NotifyDrinkConsumptionJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  # 保存済みコメントの表示通知だけを再試行する。注文・金銭処理を呼び戻さない。
  def perform(comment_id)
    comment = Comment.find(comment_id)
    return if comment.deleted_at || comment.kind != Comment::KIND_DRINK_CONSUMED

    order_id = comment.drink_order_id || comment.metadata_hash["drink_order_id"]
    order = DrinkOrder.find(order_id)
    return unless order.consumed? && order.stream_session_id == comment.stream_session_id

    DrinkOrderNotifier.replace_pending_lists(order)
    WalletNotifier.broadcast_balance_for_user(order.customer_user)
    CommentNotifier.append(comment)
  rescue StandardError => error
    Rails.logger.error("drink_consumption_notification_failed comment_id=#{comment_id} error=#{error.class.name}")
    raise
  end
end
