# frozen_string_literal: true

module StreamSessions
  class StatusService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class NoCurrentSession < Error; end
    class InvalidTransition < Error; end
    class AnotherBoothAlreadyLive < Error; end

    def initialize(booth:, actor:, to_status:, stream_session_id: nil, request_id: nil, generation: nil)
      @booth = booth
      @actor = actor
      @to_status = to_status.to_sym
      @stream_session_id = stream_session_id
      @request_id = request_id
      @generation = PublisherControl.generation(generation)
    end

    def call
      authorize!

      Stores::PublicationGuard.with_lock(booth: @booth) do
        booth = Booth.lock.find(@booth.id)

        validate_publisher_request!(booth) if PublisherControl.enabled?
        Stores::PublicationGuard.ensure_published!(booth: booth)

        raise NoCurrentSession if booth.current_stream_session_id.nil?
        raise InvalidTransition, "to_status must be live or away" unless %i[live away].include?(@to_status)

        from = booth.status.to_sym

        if @to_status == :live && another_live_booth_exists?(booth)
          raise AnotherBoothAlreadyLive, "他のブースで配信中のため開始できません"
        end

        now = Time.current

        # Issue #78 遷移
        # standby -> live（配信開始後にサーバ側でliveへ）
        # live <-> away
        # 同一はno-op
        case [ from, @to_status ]
        when %i[standby live]
          booth.update!(status: :live, last_online_at: now)
        when %i[live away]
          booth.update!(status: :away, last_online_at: now)
        when %i[away live]
          booth.update!(status: :live, last_online_at: now)
        when [ @to_status, @to_status ]
          # no-op
        else
          raise InvalidTransition, "from #{from} to #{@to_status}"
        end

        booth
      end
    end

    private

    def authorize!
      raise NotAuthorized unless @actor&.at_least?(:cast)
    end

    def validate_publisher_request!(booth)
      stream_session = booth.current_stream_session
      unless stream_session && stream_session.id.to_s == @stream_session_id.to_s &&
          PublisherControl.valid_request_id?(@request_id) && @generation
        raise PublisherControl::Error.new(code: "stale_publisher_request", message: "配信の状態が更新されています。画面を読み込み直してください", booth: booth)
      end
      stream_session.lock!
      connection = stream_session.stream_publisher_connections.lock.find_by(id: stream_session.current_publisher_connection_id)
      unless connection && connection.request_id == @request_id.downcase && connection.generation == @generation &&
          stream_session.publisher_generation == @generation && connection.released_at.nil? && connection.disconnect_requested_at.nil?
        raise PublisherControl::Error.new(code: "stale_publisher_request", message: "配信の状態が更新されています。画面を読み込み直してください", booth: booth)
      end
      unless PublisherControl.active_actor?(@actor) && stream_session.actual_publisher?(@actor) && connection.user_id == @actor.id &&
          Authorization::StreamSessionPolicy.new(@actor, stream_session).publish_token?
        raise PublisherControl::Error.new(code: "forbidden", message: "実際に配信している本人だけが状態を変更できます", booth: booth, status: :forbidden)
      end
      unless stream_session.publisher_recording_state == :recorded && connection.confirmed_at && !booth.archived? &&
          (booth.live? || booth.away?)
        raise PublisherControl::Error.new(code: "not_joinable", message: "配信開始の確認を完了してください", booth: booth)
      end
    end

    def another_live_booth_exists?(booth)
      if PublisherControl.enabled?
        return StreamSession.actually_broadcasting_by(@actor).where.not(booth_id: booth.id).exists?
      end

      Booth.active
           .joins(:current_stream_session)
           .where(stream_sessions: { started_by_cast_user_id: @actor.id })
           .where(status: %i[live away])
           .where.not(id: booth.id)
           .exists?
    end
  end
end
