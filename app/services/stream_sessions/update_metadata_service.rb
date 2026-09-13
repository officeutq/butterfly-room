module StreamSessions
  class UpdateMetadataService
    def initialize(stream_session:, actor:, attributes:)
      @session, @actor, @attributes = stream_session, actor, attributes
    end

    def call
      PublisherControl.lock_session(@session, @actor) do |session, booth|
        PublisherControl.validate!(session, booth, @actor)
        raise PublisherControl::Conflict, "スタンバイ中のみ編集できます" unless booth.standby?

        session.update!(@attributes.slice(:title))
        session
      end
    end
  end
end
