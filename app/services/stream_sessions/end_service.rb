# frozen_string_literal: true

module StreamSessions
  class EndService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class AlreadyEnded < Error; end

    def initialize(stream_session:, actor:, attempt_id: nil, force: false, client: Ivs::Client.build)
      @stream_session = stream_session
      @actor = actor
      @attempt_id, @force, @client = attempt_id, force, client
    end

    def call
      authorize!

      ended_session = nil
      ended_booth = nil
      refund_result = nil

      PublisherControl.lock_session(@stream_session, @actor) do |session, booth|
        authorize_session!(session)
        return session if session.ended? && session.ended_at.present?
        raise PublisherControl::Conflict, "現在の配信セッションと一致しません" unless booth.current_stream_session_id == session.id

        disconnect_publishers!(session, booth)
        session.stream_publish_attempts.open.update_all(cancelled_at: Time.current)
        if session.publisher_protocol.nil?
          booth.update!(publisher_blocked_until: [ booth.publisher_blocked_until, 12.hours.from_now + 1.minute ].compact.max)
        end

        booth.update!(
          status: :offline,
          current_stream_session_id: nil
        )

        refund_result = DrinkOrders::RefundService.new(stream_session: session).call!

        session.update!(ended_at: Time.current, status: :ended)

        ended_session = session
        ended_booth = booth
      end

      StreamSessionNotifier.broadcast_ended(ended_session, forced: @force)

      StreamSessionNotifier.broadcast_stream_state(booth: ended_booth)

      WalletNotifier.broadcast_balance_for_wallet_ids(refund_result&.wallet_ids)

      ended_session
    end

    private

    def authorize!
      raise NotAuthorized if @actor.blank?

      return if @actor.system_admin?
      return if @actor.cast? && BoothCast.exists?(booth_id: @stream_session.booth_id, cast_user_id: @actor.id)

      if @actor.store_admin?
        booth = Booth.find_by(id: @stream_session.booth_id)
        raise NotAuthorized if booth.blank?

        return if @actor.admin_of_store?(booth.store_id)
      end

      raise NotAuthorized
    end

    def authorize_session!(session)
      return if @force

      attempts = session.stream_publish_attempts
      if session.broadcast_started_by_user_id.present? || attempts.exists?
        attempt = attempts.find_by(request_id: @attempt_id, user: @actor)
        latest = attempts.order(:id).last
        raise NotAuthorized, "古い接続からは終了できません" unless attempt && attempt == latest
        raise NotAuthorized unless session.broadcast_started_by_user_id.nil? || session.broadcaster?(@actor)
      elsif !@actor.at_least?(:store_admin) && session.started_by_cast_user_id != @actor.id
        raise NotAuthorized
      end
    end

    def disconnect_publishers!(session, booth)
      return if session.publisher_protocol == 1 && session.stream_publish_attempts.empty? && booth.standby?
      raise PublisherControl::Conflict, "配信ルームの対応を確認できません" if session.ivs_stage_arn.blank? || session.ivs_stage_arn != booth.ivs_stage_arn

      participants = @client.list_participants(stage_arn: session.ivs_stage_arn)
      publishers = participants.select { |p| p.state == "CONNECTED" && (p.attributes || {})["role"] != "viewer" }
      if publishers.any? { |p| (p.attributes || {})["stream_session_id"] != session.id.to_s }
        raise PublisherControl::Conflict, "別セッションの接続があるため終了できません"
      end
      publishers.each do |participant|
        @client.disconnect_participant(stage_arn: session.ivs_stage_arn, participant_id: participant.participant_id)
      end
    end
  end
end
