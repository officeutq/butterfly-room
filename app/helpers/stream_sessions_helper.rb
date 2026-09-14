module StreamSessionsHelper
  def stream_session_publisher_user(stream_session)
    return unless stream_session

    if StreamSessions::PublisherControl.enabled?
      stream_session.actual_publisher_user
    else
      stream_session.started_by_cast_user
    end
  end

  def stream_session_publisher_name(stream_session)
    user = stream_session_publisher_user(stream_session)
    return display_name_or_anonymous(user) if user

    stream_session&.publisher_recording_state == :not_started ? "配信未開始" : "配信者不明"
  end

  def stream_session_publisher_link(stream_session, authenticated_viewer:)
    user = stream_session_publisher_user(stream_session)
    name = stream_session_publisher_name(stream_session)
    return name unless user && !user.deleted?

    scope = authenticated_viewer ? User.member_profiles : User.public_profiles
    return link_to(name, user_path(user), class: "text-decoration-none text-reset") if scope.exists?(id: user.id)
    return name unless authenticated_viewer

    # 管理者本人だけが閲覧できるプロフィールは、共有HTML受信後に本人の画面だけでリンクにする。
    content_tag :span, name, data: {
      controller: "self-profile-link", self_profile_link_user_id_value: user.id.to_s,
      self_profile_link_url_value: user_path(user), action: "turbo:before-cache@document->self-profile-link#reset"
    }
  end
end
