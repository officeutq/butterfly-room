# frozen_string_literal: true

module StreamSessions
  class ForceEndService
    def initialize(stream_session:, actor:)
      @stream_session, @actor = stream_session, actor
    end

    def call
      EndService.new(stream_session: @stream_session, actor: @actor, force: true).call
    rescue Aws::IVSRealTime::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      Rails.error.report(error, handled: true, source: "ivs", context: {
        log_source: "ivs", actor_user_id: @actor&.id,
        stream_session_id: @stream_session.id, store_id: @stream_session.store_id
      })
      raise
    end
  end
end
