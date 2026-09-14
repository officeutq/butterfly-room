module Ivs
  class RetryPublisherDisconnectsService
    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      unless StreamSessions::PublisherControl.active_actor?(@actor) &&
          (Authorization::BoothPolicy.new(@actor, @booth).update? ||
            StreamPublisherConnection.where(booth: @booth, user: @actor).exists?)
        raise StreamSessions::PublisherControl::Error.new(code: "forbidden",
          message: "この接続を再確認する権限がありません", booth: @booth, status: :forbidden)
      end
      self.class.pending(booth: @booth, actor: @actor).order(:id).each do |connection|
        DisconnectPublisherConnectionService.new(connection_id: connection.id).call
      end
      self.class.pending(booth: @booth, actor: @actor).exists?
    end

    def self.pending(booth:, actor:)
      scope = StreamPublisherConnection.disconnect_pending.unreleased
      scope.where(booth: booth).or(scope.where(user: actor))
    end

    def ensure_disconnected!
      return unless call

      raise StreamSessions::PublisherControl::Error.new(code: "publisher_disconnect_pending",
        message: "以前の配信接続の切断を確認しています。再確認してください", booth: @booth, status: :accepted)
    end
  end
end
