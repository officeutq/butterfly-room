module Booths
  # 管理画面の手動閉鎖。退会・所属解除の自動閉鎖とは許可する状態が異なる。
  class ArchiveService
    def initialize(booth:, actor:, stream_session_id:, generation:)
      @booth = booth
      @actor = actor
      @stream_session_id = stream_session_id
      @generation = generation
    end

    def call!
      @booth.with_lock do
        unless StreamSessions::PublisherControl.active_actor?(@actor) && @actor.at_least?(:store_admin) &&
            Authorization::BoothPolicy.new(@actor, @booth).update?
          reject!("forbidden", "ブースを閉鎖する権限がありません", status: :forbidden)
        end
        unless @stream_session_id.is_a?(String) && @stream_session_id == @booth.current_stream_session_id.to_s
          reject!("stale_publisher_request", "配信の状態が更新されています。画面を読み込み直してください")
        end
        return @booth if @booth.archived?
        if @booth.live? || @booth.away?
          reject!("not_joinable", "配信中のため閉鎖できません。先に配信を終了してください")
        end
        if @booth.standby?
          stream_session = @booth.current_stream_session
          reject!("not_joinable", "配信セッションが見つかりません") unless stream_session
          StreamSessions::EndService.new(stream_session: stream_session, actor: @actor,
            generation: @generation, mode: :force).call
          @booth.reload
        end
        unless @booth.offline? && @booth.current_stream_session_id.nil?
          reject!("not_joinable", "ブースの状態が整っていないため閉鎖できません")
        end
        @booth.update!(archived_at: Time.current)
        @booth
      end
    end

    private

    def reject!(code, message, status: :conflict)
      raise StreamSessions::PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status)
    end
  end
end
