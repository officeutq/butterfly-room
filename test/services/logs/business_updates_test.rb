# frozen_string_literal: true

require "test_helper"

class Logs::BusinessUpdatesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @store = Store.create!(name: "変更前店舗")
    @actor = User.create!(email: "log-#{SecureRandom.hex(8)}@example.com", password: "password", role: :system_admin)
    @booth = Booth.create!(store: @store, name: "変更前ブース")
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "store update records actual changes and later identical save is silent" do
    Stores::UpdateService.new(store: @store, attributes: { name: "変更後", description: "private" }, actor_user: @actor, source: "web", request_id: "update-1").call
    entry = ChangeLog.where(store_id: @store.id).sole
    assert_equal @actor.id, entry.actor_user_id
    assert_equal "web", entry.source
    assert_equal "update-1", entry.request_id
    assert_equal [ "変更前店舗", "変更後" ], entry.change_data["name"]
    assert_equal [ nil, "[FILTERED]" ], entry.change_data["description"]
    assert_no_difference "ChangeLog.count" do
      Stores::UpdateService.new(store: @store, attributes: { name: "変更後" }).call
    end
  end

  test "reload under the row lock uses the current database value instead of a stale instance" do
    Store.find(@store.id).update!(name: "別の操作の更新")
    Stores::UpdateService.new(store: @store, attributes: { name: "今回の更新" }).call
    assert_equal [ "別の操作の更新", "今回の更新" ], ChangeLog.where(store_id: @store.id).sole.change_data["name"]
  end

  test "booth creation and editing share the same log table" do
    new_booth = @store.booths.new
    Booths::UpdateService.new(booth: new_booth, attributes: { name: "新規ブース" }, actor_user: @actor).call
    assert_equal "created", ChangeLog.where(target_type: "Booth", target_id: new_booth.id).sole.action
    Booths::UpdateService.new(booth: @booth, attributes: { name: "編集済み" }, actor_user: @actor).call
    entry = ChangeLog.where(target_type: "Booth", target_id: @booth.id).sole
    assert_equal "updated", entry.action
    assert_equal [ "変更前ブース", "編集済み" ], entry.change_data["name"]
  end

  test "a blank but valid booth creation still has a creation event" do
    booth = @store.booths.new
    Booths::UpdateService.new(booth:, attributes: { name: "" }).call
    assert_equal "created", ChangeLog.where(target_type: "Booth", target_id: booth.id).sole.action
  end

  test "invalid update does not write a successful history" do
    assert_no_difference "ChangeLog.count" do
      assert_raises(ActiveRecord::RecordInvalid) { Stores::UpdateService.new(store: @store, attributes: { name: "" }).call }
    end
    assert_equal "変更前店舗", @store.reload.name
  end

  test "caller block failure cancels the save and history" do
    assert_no_difference "ChangeLog.count" do
      assert_raises(RuntimeError) do
        @booth.transaction(requires_new: true) do
          Booths::UpdateService.new(booth: @booth, attributes: { name: "取消" }).call { raise "caller failed" }
        end
      end
    end
    assert_equal "変更前ブース", @booth.reload.name
  end

  test "required history failure cancels the real update" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @store.transaction(requires_new: true) do
        Stores::UpdateService.new(store: @store, attributes: { name: "取消" }, source: "invalid").call
      end
    end
    assert_includes @store.errors.full_messages.join, "変更履歴を保存できなかった"
    assert_equal "変更前店舗", @store.reload.name
  end

  test "multipart image removal and attributes produce a single history" do
    @store.thumbnail.attach(io: File.open(file_fixture("sample.jpg")), filename: "private-name.jpg", content_type: "image/jpeg")
    old_id = @store.thumbnail.blob.id
    expected = ImageAttachments::StagedPairUpdateService.capture(record: @store, purpose: :thumbnail).to_h
    Stores::UpdateService.new(store: @store, attributes: { name: "画像削除" }, image_update: { operation: "delete", expected: }).call
    entry = ChangeLog.where(store_id: @store.id).sole
    assert_equal [ { "source_blob_id" => nil, "display_blob_id" => old_id }, nil ], entry.change_data["thumbnail"]
    assert_equal [ "変更前店舗", "画像削除" ], entry.change_data["name"]
    assert_not_includes entry.to_json, "private-name"
  end

  test "stale image snapshot leaves attributes and history unchanged" do
    expected = ImageAttachments::StagedPairUpdateService.capture(record: @store, purpose: :thumbnail).to_h
    @store.thumbnail.attach(io: File.open(file_fixture("sample.jpg")), filename: "existing.jpg", content_type: "image/jpeg")
    assert_no_difference "ChangeLog.count" do
      assert_raises(Stores::UpdateService::StaleImageError) do
        Stores::UpdateService.new(store: @store, attributes: { name: "取消" }, image_update: { operation: "delete", expected: }).call
      end
    end
    assert_equal "変更前店舗", @store.reload.name
    assert @store.thumbnail.attached?
  end
end
