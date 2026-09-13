require "test_helper"

class StreamSessions::LegacyBroadcasterBackfillTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Backfill")
    @x = User.create!(email: "backfill-x@example.test", password: "password", role: :cast)
    @y = User.create!(email: "backfill-y@example.test", password: "password", role: :cast)
    @booth = Booth.create!(store: @store, name: "Backfill", status: :offline)
    @cutoff = Time.current.change(usec: 0) - 1.hour
  end

  def old_session(**attributes)
    StreamSession.create!({ booth: @booth, store: @store, started_by_cast_user: @x,
      created_at: @cutoff - 2.hours, started_at: @cutoff - 2.hours,
      broadcast_started_at: @cutoff - 90.minutes, ended_at: @cutoff - 1.hour, status: :ended }.merge(attributes))
  end

  def plan
    StreamSessions::LegacyBroadcasterBackfill.preview(cutoff: @cutoff.iso8601)
  end

  def batch(manifest)
    StreamSessions::LegacyBroadcasterBackfill.new(manifest: manifest)
  end

  test "dry run changes nothing and apply only fills ended old broadcasts with a start record" do
    eligible = old_session
    excluded = [
      old_session(broadcast_started_at: nil),
      old_session(status: :live, ended_at: nil),
      old_session(ended_at: @cutoff + 1.minute),
      old_session(created_at: @cutoff + 1.minute),
      old_session(publisher_protocol: 1),
      old_session(broadcast_started_by_user: @y, broadcast_identity_source: "ivs_confirmed"),
      old_session(ended_at: @cutoff - 3.hours)
    ]
    current = old_session
    @booth.update!(current_stream_session: current)
    excluded << current
    before = eligible.attributes
    excluded_before = excluded.to_h { |s| [ s.id, s.attributes ] }
    manifest = plan
    assert_equal 1, manifest["counts"]["eligible"]
    assert_equal before, eligible.reload.attributes
    result = batch(JSON.parse(JSON.generate(manifest))).apply
    assert_equal [ "updated" ], result.map { |r| r[:result] }
    assert eligible.reload.broadcaster?(@x)
    assert_equal "legacy_creator_backfill", eligible.broadcast_identity_source
    assert_equal before.except("broadcast_started_by_user_id", "broadcast_identity_source", "broadcast_identity_evidence"),
      eligible.attributes.except("broadcast_started_by_user_id", "broadcast_identity_source", "broadcast_identity_evidence")
    excluded.each { |s| assert_equal excluded_before[s.id], s.reload.attributes }
    assert_equal [ "already_recorded" ], batch(manifest).apply.map { |r| r[:result] }
  end

  test "fixed snapshot excludes subsequently added or changed records and preserves evidence" do
    changed = old_session
    confirmed = old_session
    manifest = plan
    added = old_session
    changed.update!(ended_at: @cutoff + 1.minute)
    confirmed.update!(broadcast_started_by_user: @y, broadcast_identity_source: "evidence")
    batch(manifest).apply
    assert_nil added.reload.broadcast_started_by_user_id
    assert_nil changed.reload.broadcast_started_by_user_id
    assert confirmed.reload.broadcaster?(@y)
  end

  test "rollback only undoes this plan and preserves later evidence corrections" do
    target = old_session
    corrected = old_session
    manifest = plan
    batch(manifest).apply
    corrected.update!(broadcast_started_by_user: @y, broadcast_identity_source: "evidence")
    batch(manifest).rollback
    assert_nil target.reload.broadcast_started_by_user_id
    assert target.broadcast_identity_evidence["backfill_reverted_at"]
    assert corrected.reload.broadcaster?(@y)
  end

  test "evidence correction changes only identified legacy identity and selected consumed comment" do
    target = old_session
    consumed = target.comments.create!(booth: @booth, user: @x, kind: Comment::KIND_DRINK_CONSUMED)
    chat = target.comments.create!(booth: @booth, user: @x, kind: Comment::KIND_CHAT, body: "本人の発言")
    correction = { stream_session_id: target.id, from_user_id: nil, from_source: nil, to_user_id: @y.id,
      evidence_reference: "reviewed-ivs-record.json", reason: "IVSの配信済み参加者属性を照合",
      comments: [ { id: consumed.id, from_user_id: @x.id } ] }
    service = StreamSessions::BroadcasterEvidenceService.new(plan: correction)
    result = service.preview
    assert_nil target.reload.broadcast_started_by_user_id
    assert_equal 0, result[:store_sales_delta]
    service.apply
    assert target.reload.broadcaster?(@y)
    assert_equal @y.id, consumed.reload.user_id
    assert_equal @x.id, chat.reload.user_id
    assert_equal "already_applied", service.apply[:result]
    assert target.broadcast_identity_evidence["corrections"].sole["plan"]["evidence_reference"]
  end

  test "evidence correction rejects ordinary comments and stale identity" do
    target = old_session
    chat = target.comments.create!(booth: @booth, user: @x, body: "変更不可")
    correction = { stream_session_id: target.id, from_user_id: nil, from_source: nil, to_user_id: @y.id,
      evidence_reference: "reviewed-ivs-record.json", reason: "属性照合", comments: [ { id: chat.id, from_user_id: @x.id } ] }
    assert_raises(ArgumentError) { StreamSessions::BroadcasterEvidenceService.new(plan: correction).apply }
    assert_nil target.reload.broadcast_started_by_user_id
    correction[:comments] = []
    target.update!(broadcast_started_by_user: @x, broadcast_identity_source: "legacy_creator_backfill")
    assert_raises(ArgumentError) { StreamSessions::BroadcasterEvidenceService.new(plan: correction).apply }
  end

  test "IVS investigation distinguishes missing unique and conflicting evidence without changing DB" do
    target = old_session
    participant = Struct.new(:participant_id, :attributes, :published, :user_id)
    stage = Struct.new(:session_id, :start_time, :end_time).new("old-stage-session", target.started_at, target.ended_at)
    records = []
    client = Object.new
    client.define_singleton_method(:list_stage_sessions) { |**| [ stage ] }
    client.define_singleton_method(:list_participants) { |**| records }
    investigate = -> { StreamSessions::BroadcasterEvidenceService.investigate(target, client: client) }
    assert_equal "unknown", investigate.call[:classification]
    records << participant.new("p-y", { "role" => "publisher", "stream_session_id" => target.id.to_s, "user_id" => @y.id.to_s }, true, @y.id.to_s)
    assert_equal "identified", investigate.call[:classification]
    assert_equal @y.id, investigate.call[:proposed_user_id]
    records << participant.new("p-x", { "role" => "publisher", "stream_session_id" => target.id.to_s, "user_id" => @x.id.to_s }, true, @x.id.to_s)
    assert_equal "ambiguous", investigate.call[:classification]
    assert_nil investigate.call[:proposed_user_id]
    assert_nil target.reload.broadcast_started_by_user_id
  end
end
