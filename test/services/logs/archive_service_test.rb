# frozen_string_literal: true

require "test_helper"

class Logs::ArchiveServiceTest < ActiveSupport::TestCase
  setup do
    @request_id = SecureRandom.uuid
    @now = Time.current.change(usec: 0)
  end

  teardown do
    ErrorLog.where(request_id: @request_id).delete_all
  end

  test "dry run is the default and apply archives a bounded batch without changing history" do
    oldest = change(occurred_at: @now - 367.days)
    older = change(occurred_at: @now - 366.days)
    boundary = change(occurred_at: @now - 365.days)
    before = oldest.attributes.except("archived_at")
    result = Logs::ArchiveService.call(kind: :changes, limit: 1, now: @now)
    assert_equal 1, result.candidate_count
    assert_equal 0, result.archived_count
    assert_nil oldest.reload.archived_at

    assert_no_difference "ChangeLog.count" do
      result = Logs::ArchiveService.call(kind: :changes, limit: 1, apply: true, now: @now)
      assert_equal 1, result.archived_count
    end
    assert_equal @now, oldest.reload.archived_at
    assert_equal before, oldest.attributes.except("archived_at")
    assert_nil older.reload.archived_at
    assert_nil boundary.reload.archived_at
    assert_equal 1, Logs::ArchiveService.call(kind: :changes, apply: true, now: @now).archived_count
    assert_equal 0, Logs::ArchiveService.call(kind: :changes, apply: true, now: @now).archived_count
    assert_nil boundary.reload.archived_at

    page = Logs::SearchQuery.new(kind: :changes, filters: {
      from: (@now.to_date - 368).iso8601, to: (@now.to_date - 365).iso8601,
      archive: "archived", request_id: @request_id
    }).call
    assert_equal [ older.id, oldest.id ], page.records.map(&:id)
  end

  test "errors use a separate ninety-day threshold" do
    old = error(occurred_at: @now - 91.days)
    boundary = error(occurred_at: @now - 90.days)
    assert_no_difference "ErrorLog.count" do
      result = Logs::ArchiveService.call(kind: :errors, apply: true, now: @now)
      assert_equal 1, result.archived_count
    end
    assert_equal @now, old.reload.archived_at
    assert_nil boundary.reload.archived_at
  end

  test "invalid kinds limits and implicit apply values are refused" do
    assert_raises(KeyError) { Logs::ArchiveService.call(kind: :users) }
    [ 0, -1, 10_001, "all" ].each do |limit|
      assert_raises(ArgumentError) { Logs::ArchiveService.call(kind: :changes, limit: limit) }
    end
    assert_raises(ArgumentError) { Logs::ArchiveService.call(kind: :changes, apply: "true") }
  end

  private

  def change(**attributes)
    ChangeLog.create!({ occurred_at: @now, source: "application", request_id: @request_id,
      target_type: "Store", target_id: 999, actor_user_id: 888, store_id: 999,
      action: "updated", change_data: { name: [ "前", "後" ] } }.merge(attributes))
  end

  def error(**attributes)
    ErrorLog.create!({ occurred_at: @now, source: "application", request_id: @request_id,
      severity: "error", exception_class: "RuntimeError", summary: "安全な要約" }.merge(attributes))
  end
end
