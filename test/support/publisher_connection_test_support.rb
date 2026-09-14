module PublisherConnectionTestSupport
  def build_publisher_fixture
    suffix = SecureRandom.hex(6)
    @store = Store.create!(name: "Publisher claims #{suffix}", published: true)
    @creator = User.create!(email: "claim-creator-#{suffix}@example.com", password: "password", role: :cast)
    @publisher = User.create!(email: "claim-publisher-#{suffix}@example.com", password: "password", role: :store_admin)
    @other_publisher = User.create!(email: "claim-other-#{suffix}@example.com", password: "password", role: :store_admin)
    [ @publisher, @other_publisher ].each { |user| StoreMembership.create!(store: @store, user: user, membership_role: :admin) }
    @booth = build_prepared_booth("first-#{suffix}")
    @stream_session = @booth.current_stream_session
    @ivs_client = Aws::IVSRealTime::Client.new(stub_responses: true)
    @ivs_client.stub_responses(:get_stage, ->(context) { { stage: { arn: context.params[:arn] } } })
    sequence = 0
    mutex = Mutex.new
    @ivs_client.stub_responses(:create_participant_token, ->(_context) {
      number = mutex.synchronize { sequence += 1 }
      { participant_token: { token: "test-token-#{number}", participant_id: "test-participant-#{number}", expiration_time: 1.hour.from_now } }
    })
  end

  def build_prepared_booth(name)
    booth = Booth.create!(store: @store, name: name, status: :standby,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}")
    BoothCast.create!(booth: booth, cast_user: @creator)
    stream_session = StreamSession.create!(booth: booth, store: @store, started_by_cast_user: @creator,
      status: :live, started_at: 10.minutes.ago, title: "旧準備", ivs_stage_arn: booth.ivs_stage_arn)
    booth.update!(current_stream_session: stream_session)
    booth
  end

  def with_publisher_client(enabled: "true")
    original_constructor = Aws::IVSRealTime::Client.method(:new)
    client = @ivs_client
    Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => enabled) { yield }
  ensure
    Aws::IVSRealTime::Client.define_singleton_method(:new, original_constructor)
  end

  def issue_token(actor: @publisher, stream_session: @stream_session, request_id: SecureRandom.uuid, generation: 0)
    StreamSessions::IssuePublisherConnectionService.new(stream_session: stream_session, actor: actor,
      request_id: request_id, expected_generation: generation).call
  end

  def cancel_token(result, actor: @publisher, stream_session: @stream_session)
    StreamSessions::CancelPublisherConnectionService.new(stream_session: stream_session, actor: actor,
      request_id: result[:request_id], generation: result[:generation]).call
  end

  def issued_count
    @ivs_client.api_requests.count { |request| request[:operation_name] == :create_participant_token }
  end

  def disconnect_requests
    @ivs_client.api_requests.select { |request| request[:operation_name] == :disconnect_participant }.map { |request| request[:params] }
  end

  def stub_published_participant(result, attributes: {}, published: true, extra_participants: [])
    participant = { participant_id: result[:participant_id], state: "CONNECTED", published: published,
      attributes: { "role" => "publisher", "stream_session_id" => @stream_session.id.to_s, "user_id" => @publisher.id.to_s }.merge(attributes) }
    participants = [ participant, *extra_participants ]
    @ivs_client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn, active_session_id: "ivs-session" } })
    @ivs_client.stub_responses(:list_participants, { participants: participants.map { |entry| entry.except(:attributes) } })
    @ivs_client.stub_responses(:get_participant, ->(context) {
      { participant: participants.find { |entry| entry[:participant_id] == context.params[:participant_id] } }
    })
  end

  def confirm_token(result, actor: @publisher)
    StreamSessions::ConfirmPublisherService.new(stream_session: @stream_session, actor: actor,
      request_id: result[:request_id], generation: result[:generation]).call
  end
end
