# frozen_string_literal: true

require "test_helper"

class Logs::SearchQueryTest < ActiveSupport::TestCase
  setup do
    @request_id = SecureRandom.uuid
  end

  test "date boundaries include the whole final day in Japan time" do
    before = entry(occurred_at: Time.iso8601("2026-09-09T23:59:59+09:00"))
    first = entry(occurred_at: Time.iso8601("2026-09-10T00:00:00+09:00"))
    last = entry(occurred_at: Time.iso8601("2026-09-10T23:59:59.999999+09:00"))
    after = entry(occurred_at: Time.iso8601("2026-09-11T00:00:00+09:00"))
    result = search(from: "2026-09-10", to: "2026-09-10")
    assert_empty result.errors
    assert_equal [ last.id, first.id ], result.records.map(&:id)
    assert_not_includes result.records.map(&:id), before.id
    assert_not_includes result.records.map(&:id), after.id
  end

  test "default date window is seven Japan calendar days" do
    travel_to Time.iso8601("2026-09-12T00:15:00+09:00") do
      old = entry(occurred_at: Time.iso8601("2026-09-05T23:59:59+09:00"))
      current = entry(occurred_at: Time.iso8601("2026-09-06T00:00:00+09:00"))
      result = search
      assert_equal "2026-09-06", result.filters["from"]
      assert_equal "2026-09-12", result.filters["to"]
      assert_equal [ current.id ], result.records.map(&:id)
      assert_not_includes result.records.map(&:id), old.id
    end
  end

  test "invalid filters never return an unbounded or broadened result" do
    entry
    [ { from: "2026-02-30" }, { from: "2025-01-01", to: "2026-01-02" },
      { from: "2026-09-12", to: "2026-09-11" }, { page: "1001" }, { page: "0" },
      { store_id: "9223372036854775808" }, { target_id: "1 OR 1=1" },
      { target_type: "User" }, { change_action: "destroyed" }, { source: "invalid" },
      { request_id: "x' OR 1=1" }, { archive: "other" } ].each do |filters|
      result = search(**filters)
      assert_not_empty result.errors, filters.inspect
      assert_empty result.records, filters.inspect
    end
    assert_empty search(from: "2025-01-01", to: "2026-01-01").errors
  end

  test "pagination is stable and does not load detail payloads" do
    timestamp = Time.current
    entries = Array.new(52) { entry(occurred_at: timestamp) }
    first = search
    second = search(page: "2")
    assert_equal entries.reverse.first(50).map(&:id), first.records.map(&:id)
    assert first.has_next
    assert_equal entries.reverse.last(2).map(&:id), second.records.map(&:id)
    assert_not second.has_next
    assert_not first.records.first.has_attribute?(:change_data)
  end

  test "common and change-specific filters combine with archive selection" do
    wanted = entry(actor_user_id: 42, store_id: 9, target_type: "Booth", target_id: 13, action: "created", source: "web", archived_at: Time.current)
    entry(actor_user_id: 43, store_id: 9, target_type: "Booth", target_id: 13, action: "created", source: "web")
    assert_not_includes search.records.map(&:id), wanted.id
    filters = { actor_user_id: "42", store_id: "9", target_type: "Booth", target_id: "13", change_action: "created", source: "web" }
    assert_equal [ wanted.id ], search(**filters, archive: "archived").records.map(&:id)
    assert_equal [ wanted.id ], search(**filters, archive: "all").records.map(&:id)
    assert_empty search(**filters).records
  end

  private

  def entry(**attributes)
    ChangeLog.create!({ occurred_at: Time.current, source: "application", request_id: @request_id,
      target_type: "Store", target_id: 1, action: "updated", change_data: { name: [ "前", "後" ] } }.merge(attributes))
  end

  def search(**filters)
    Logs::SearchQuery.new(kind: :changes, filters: { request_id: @request_id }.merge(filters)).call
  end
end
