module PublisherTestHelper
  # 表示・終了のテスト用に、指定した本人の確定済みDB記録を明示的に用意する。
  # IVSの成功判定そのものはPublishServiceTestで検証する。
  def record_confirmed_broadcast!(session, user:)
    session.update!(publisher_protocol: 1, broadcast_started_by_user: user,
      broadcast_started_at: session.broadcast_started_at || Time.current, broadcast_identity_source: "ivs_confirmed")
    session.stream_publish_attempts.create!(user: user, request_id: SecureRandom.uuid,
      participant_id: "test-participant-#{session.id}", expires_at: 1.minute.from_now, confirmed_at: Time.current)
  end
end
