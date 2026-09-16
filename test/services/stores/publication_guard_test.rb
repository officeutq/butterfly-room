require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Stores::PublicationGuardTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport
  setup { build_publisher_fixture }

  test "非公開店舗では全役割の新規準備と既存準備への入室とトークン発行を拒否する" do
    @booth.store # 古い関連オブジェクトが公開中でも、DBの最新状態で確認する。
    unpublish
    @publisher.update!(role: :system_admin)
    with_publisher_client do
      [ @creator, @other_publisher, @publisher ].each do |actor|
        operations = [
          -> { StreamSessions::StartService.new(booth: @booth, actor: actor).call },
          -> { Booths::EnterAsCastService.new(booth: @booth, actor: actor).call },
          -> { issue_token(actor: actor) }
        ]
        operations.each do |operation|
          error = assert_raises(StreamSessions::PublisherControl::Error, &operation)
          assert_equal "store_unpublished", error.code
        end
        entry = Booths::PrepareSelectedBoothService.new(booth: @booth, actor: actor).call
        assert entry.information_only
        assert_equal Stores::PublicationGuard::MESSAGE, entry.message
      end
      assert_empty @ivs_client.api_requests
      assert_equal 0, StreamPublisherConnection.where(booth: @booth).count
      assert @booth.reload.standby?
    end
  end

  test "準備中の非公開化は同じ準備を残し再公開すれば開始できる" do
    before = @stream_session.attributes
    unpublish
    assert_equal before, @stream_session.reload.attributes
    assert @booth.reload.standby?
    Stores::UpdateService.new(store: @store, attributes: { published: true }).call
    with_publisher_client { assert_equal "issued", issue_token[:state] }
  end

  test "開始処理中は非公開化と他の属性変更をまとめて拒否し取消後は許可する" do
    with_publisher_client do
      issued = issue_token
      old_name = @store.name
      assert_raises(Stores::UpdateService::UnpublishBlocked) do
        Stores::UpdateService.new(store: @store, attributes: { published: false, name: "保存されない名前" }).call
      end
      assert_includes @store.errors.full_messages.join, "開始処理中"
      assert @store.reload.published?
      assert_equal old_name, @store.name
      assert_equal "cancelled", cancel_token(issued)[:state]
      unpublish
      refute @store.reload.published?
      assert @booth.reload.standby?
    end
  end

  %i[live away].each do |status|
    test "#{status}中は店舗内の別ブースであっても非公開化できず終了後は許可する" do
      with_publisher_client do
        issued = issue_token
        stub_published_participant(issued)
        confirm_token(issued)
        @booth.update!(status: status)
        build_prepared_booth("another-booth")
        assert_raises(Stores::UpdateService::UnpublishBlocked) { unpublish }
        assert @store.reload.published?
        assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
        StreamSessions::EndService.new(stream_session: @stream_session, actor: @publisher,
          request_id: issued[:request_id], generation: issued[:generation]).call
        unpublish
        refute @store.reload.published?
      end
    end
  end

  test "通常編集以外で非公開になっても古い開始確定と旧配信入口は拒否する" do
    with_publisher_client do
      issued = issue_token
      @store.update!(published: false)
      error = assert_raises(StreamSessions::PublisherControl::Error) { confirm_token(issued) }
      assert_equal "store_unpublished", error.code
      assert_nil @stream_session.reload.actual_publisher_user_id
      # 取消と終了の経路は非公開を理由に塞がない。
      assert_equal "cancelled", cancel_token(issued)[:state]
    end
    with_publisher_client(enabled: "false") do
      error = assert_raises(StreamSessions::PublisherControl::Error) do
        Ivs::CreateParticipantTokenService.new(stream_session: @stream_session, actor: @creator, role: "publisher").call
      end
      assert_equal "store_unpublished", error.code
      assert_raises(StreamSessions::PublisherControl::Error) do
        StreamSessions::StatusService.new(booth: @booth, actor: @creator, to_status: :live).call
      end
    end
  end

  private

  def unpublish
    Stores::UpdateService.new(store: @store, attributes: { published: false }).call
  end
end
