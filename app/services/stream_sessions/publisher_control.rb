# frozen_string_literal: true

module StreamSessions
  # 招待承認なども with_user_lock の中で busy_elsewhere? を再確認する。
  # ロック順序は利用者 → ブース → セッション。外部照会中も開始権を保持する。
  class PublisherControl
    class Conflict < StandardError; end
    class NotAuthorized < StandardError; end

    def self.with_user_lock(user, &block)
      raise NotAuthorized, "配信権限がありません" unless user

      User.transaction do
        user.reload(lock: true)
        block.call
      end
    end

    def self.busy_elsewhere?(user, booth:)
      StreamPublishAttempt.open.joins(:stream_session).where(user: user)
        .where.not(stream_sessions: { booth_id: booth.id }).exists? ||
        Booth.joins(:current_stream_session).where.not(id: booth.id)
          .where(stream_sessions: { broadcast_started_by_user_id: user.id }).exists? ||
        unknown_legacy_elsewhere?(user, booth: booth)
    end

    def self.unknown_legacy_elsewhere?(user, booth:)
      # 旧配信で本人か判断できない場合は、配信可能だった範囲を保守的に占有扱いする。
      Booth.joins(:current_stream_session).where.not(id: booth.id)
        .where(stream_sessions: { publisher_protocol: nil, broadcast_started_by_user_id: nil })
        .includes(:current_stream_session).any? do |candidate|
          Authorization::StreamSessionPolicy.new(user, candidate.current_stream_session).publish_token?
        end
    end

    def self.release_expired_attempts!(user, booth: nil, client: Ivs::Client.build)
      attempts = StreamPublishAttempt.open.where("expires_at < ?", Time.current)
      attempts = if booth
        attempts.where("user_id = ? OR stream_session_id IN (?)", user.id, StreamSession.where(booth_id: booth.id).select(:id))
      else
        attempts.where(user: user)
      end
      attempts.each do |attempt|
        participants = client.list_participants(stage_arn: attempt.stream_session.ivs_stage_arn)
        next if participants.any? { |p| p.state != "DISCONNECTED" && (p.attributes || {})["role"] != "viewer" }

        attempt.update!(retired_at: Time.current)
      end
    end

    def self.available_to?(session, user)
      return false unless session && user && session.live? && session.ended_at.nil?
      return false if session.broadcast_started_by_user_id.present? && !session.broadcaster?(user)
      return false if session.publisher_protocol != 1
      return false if session.broadcast_started_by_user_id.nil? && (session.broadcast_started_at.present? || session.booth.live? || session.booth.away?)

      !session.stream_publish_attempts.open.where.not(user: user).exists?
    end

    def self.lock_session(session, user)
      with_user_lock(user) do
        booth = Booth.lock.find(session.booth_id)
        current = StreamSession.lock.find(session.id)
        yield current, booth
      end
    end

    def self.validate!(session, booth, user)
      raise NotAuthorized, "配信権限がありません" unless Authorization::StreamSessionPolicy.new(user, session).publish_token?
      unless !booth.archived? && booth.current_stream_session_id == session.id &&
          %w[standby live away].include?(booth.status) && session.live? && session.ended_at.nil? &&
          session.ivs_stage_arn.present? && session.ivs_stage_arn == booth.ivs_stage_arn
        raise Conflict, "配信セッションの状態が変わりました。画面を再読み込みしてください"
      end
      raise Conflict, "別の配信者が使用中、または旧配信の確認が必要です" unless available_to?(session, user)
      raise Conflict, "他のブースで配信中です" if busy_elsewhere?(user, booth: booth)
      if booth.publisher_blocked_until && booth.publisher_blocked_until > Time.current
        raise Conflict, "旧配信の接続有効期間が終了するまで配信を開始できません"
      end
    end
  end
end
