# frozen_string_literal: true

module StreamSessions
  class EndService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class AlreadyEnded < Error; end

    def initialize(stream_session:, actor:)
      @stream_session = stream_session
      @actor = actor
    end

    def call
      authorize!

      ended_session = nil
      ended_booth = nil
      refund_result = nil

      StreamSession.transaction do
        session = StreamSession.lock.find(@stream_session.id)
        raise AlreadyEnded if session.ended_at.present?

        booth = Booth.lock.find(session.booth_id)

        # boothをoffline化 + current_stream_session_id解除
        booth.update!(
          status: :offline,
          current_stream_session_id: nil
        )

        refund_result = DrinkOrders::RefundService.new(stream_session: session).call!

        session.update!(ended_at: Time.current, status: :ended)

        ended_session = session
        ended_booth = booth
      end

      StreamSessionNotifier.broadcast_ended(ended_session)

      # ★Issue42: booth単位のUIを「未配信」に自動切替（リロード不要）
      StreamSessionNotifier.broadcast_stream_state(booth: ended_booth)

      # ★Issue146: 返却が発生したユーザーの wallet 残高を個人チャンネルで更新
      WalletNotifier.broadcast_balance_for_wallet_ids(refund_result&.wallet_ids)

      ended_session
    end

    private

    def authorize!
      raise NotAuthorized if @actor.blank?

      # system_admin は常にOK
      return if @actor.system_admin?

      # cast は従来どおりOK
      return if @actor.cast?

      # store_admin は「対象storeのadminであること」が必須
      if @actor.store_admin?
        booth = Booth.find_by(id: @stream_session.booth_id)
        raise NotAuthorized if booth.blank?

        return if @actor.admin_of_store?(booth.store_id)
      end

      raise NotAuthorized
    end
  end
end
