module StreamSessionsHelper
  def stream_broadcaster_name(stream_session)
    user = stream_session.broadcast_started_by_user
    user ? display_name_or_anonymous(user) : stream_session.broadcaster_label
  end
end
