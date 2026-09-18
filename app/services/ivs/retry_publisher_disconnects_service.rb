module Ivs
  class RetryPublisherDisconnectsService
    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      authorize!
      self.class.pending(booth: @booth, actor: @actor).order(:id).each do |connection|
        DisconnectPublisherConnectionService.new(connection_id: connection.id).call
      end
      self.class.pending(booth: @booth, actor: @actor).exists?
    end

    # 情報画面は対象ブースだけを表示する。準備・開始側は本人の別ブースの未切断も含める。
    def state(booth_only: false)
      authorize!(allow_previous_publisher: !booth_only)
      scope = self.class.pending(booth: @booth, actor: @actor)
      scope = scope.where(booth: @booth) if booth_only
      self.class.state_for(scope)
    end

    def self.state_for(scope)
      states = scope.to_a.map(&:disconnect_state)
      failed = states.include?("failed")
      pending = failed || states.include?("retrying")
      { disconnect_pending: pending, disconnect_state: failed ? "failed" : (pending ? "retrying" : "disconnected"),
        message: failed ? "配信接続の切断を確認できませんでした。運用担当者へお問い合わせください。" :
          (pending ? "配信接続の切断を再試行しています。次の配信は切断確認後に開始できます。" : "配信接続の切断を確認しました。") }
    end

    def authorize!(allow_previous_publisher: true)
      unless StreamSessions::PublisherControl.active_actor?(@actor) &&
          (Authorization::BoothPolicy.new(@actor, @booth).update? ||
            (allow_previous_publisher && StreamPublisherConnection.where(booth: @booth, user: @actor).exists?))
        raise StreamSessions::PublisherControl::Error.new(code: "forbidden",
          message: "この接続を再確認する権限がありません", booth: @booth, status: :forbidden)
      end
    end

    def self.pending(booth:, actor:)
      scope = StreamPublisherConnection.disconnect_pending.unreleased
      scope.where(booth: booth).or(scope.where(user: actor))
    end

    def ensure_disconnected!
      return unless call

      raise StreamSessions::PublisherControl::Error.new(code: "publisher_disconnect_pending",
        message: self.class.pending(booth: @booth, actor: @actor).any? { |connection| connection.disconnect_state == "failed" } ?
          "以前の配信接続の切断を確認できませんでした。運用担当者へお問い合わせください" :
          "以前の配信接続の切断を確認しています。しばらくお待ちください", booth: @booth, status: :accepted)
    end
  end
end
