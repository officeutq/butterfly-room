module Booths
  # 選択したブースの情報確認と配信準備を分ける。配信可否の本体は既存Serviceに委譲する。
  class PrepareSelectedBoothService
    CLOSED_MESSAGE = "閉鎖済みのブースでは配信準備・配信開始はできません".freeze
    Result = Struct.new(:booth, :information_only, :message, keyword_init: true)

    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      @booth.with_lock do
        unless StreamSessions::PublisherControl.active_actor?(@actor) && Authorization::BoothPolicy.new(@actor, @booth).update?
          raise EnterAsCastService::NotAuthorized, "選択できないブースです"
        end
        if @booth.archived?
          raise ActiveRecord::RecordNotFound unless @actor.at_least?(:store_admin)
          return information(CLOSED_MESSAGE)
        end

        entry = EnterAsCastService.new(booth: @booth, actor: @actor).call
        case entry.action
        when :redirect_live
          Result.new(booth: entry.booth, information_only: false)
        when :occupied_by_other
          information("このブースはすでに他の人が配信中です")
        else
          raise StreamSessions::PublisherControl::Error.new(code: "publisher_in_use",
            message: "他のブースで配信中のため開始できません", booth: @booth)
        end
      end
    rescue StreamSessions::PublisherControl::Error => error
      # 共通制御が拒否したうち、対象の実配信者が別人と確定した場合だけ情報確認へ進める。
      # 本人の別ブース配信・不整合・通信失敗は成功として扱わない。
      stream = @booth.reload.current_stream_session
      if error.code == "publisher_in_use" && stream&.publisher_recording_state == :recorded && !stream.actual_publisher?(@actor)
        information(error.message)
      else
        raise
      end
    end

    private

    def information(message)
      Result.new(booth: @booth, information_only: true, message: message)
    end
  end
end
