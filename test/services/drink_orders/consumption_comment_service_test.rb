require "test_helper"
require_relative "../../support/consumption_test_support"

class DrinkOrders::ConsumptionCommentServiceTest < ActiveSupport::TestCase
  include ConsumptionTestSupport
  setup { build_consumption_fixture }

  test "H04 不明な旧実績の消化通知だけにNULL投稿者を保存してリンクなしで表示する" do
    @session.update!(actual_publisher_user: nil, actual_publisher_source: nil, actual_publisher_recorded_at: nil,
      status: :ended, ended_at: Time.current)
    @order.update!(status: :consumed, consumed_at: 1.minute.ago)
    comment = DrinkOrders::ConsumptionCommentService.new(drink_order: @order).call!
    assert_nil comment.user
    assert_equal true, comment.metadata["publisher_unknown"]
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      [ false, true ].each do |guest|
        html = ApplicationController.render(partial: "comments/comment", locals: { comment: comment, guest_viewer: guest })
        fragment = Nokogiri::HTML.fragment(html)
        assert_includes fragment.text, "配信者不明"
        assert_empty fragment.css(".comment-author a, [data-controller='self-profile-link'], .comment-from-broadcaster")
      end
    end
    assert_equal comment.id, DrinkOrders::ConsumptionCommentService.new(drink_order: @order).call!.id
  end

  test "H02 既存metadataの旧消化通知を更新せず再利用し論理削除後も重複作成しない" do
    @order.update!(status: :consumed, consumed_at: Time.current)
    [ @order.id, @order.id.to_s ].each do |metadata_id|
      @session.comments.delete_all
      old = Comment.create!(stream_session: @session, booth: @booth, user: @creator,
        kind: Comment::KIND_DRINK_CONSUMED, metadata: { drink_order_id: metadata_id }, deleted_at: Time.current)
      before = old.attributes
      assert_no_difference "Comment.count" do
        result = DrinkOrders::ConsumptionCommentService.new(drink_order: @order).call!
        assert_equal old.id, result.id
      end
      assert_equal before, old.reload.attributes
    end
  end

  test "H04 通常コメントのuser必須をモデルとDBの両方で維持する" do
    Comment::KINDS.each do |kind|
      [ {}, { "publisher_unknown" => false }, { "publisher_unknown" => "true" }, { "publisher_unknown" => true } ].each do |metadata|
        next if kind == Comment::KIND_DRINK_CONSUMED && metadata["publisher_unknown"] == true

        comment = Comment.new(stream_session: @session, booth: @booth, user: nil,
          kind: kind, body: "body", metadata: metadata)
        refute comment.valid?, "#{kind} #{metadata}"
        assert_raises(ActiveRecord::StatementInvalid) do
          Comment.transaction(requires_new: true) { comment.save!(validate: false) }
        end
      end
    end
  end

  test "H02 注文FKと値ありの一意制約が直接書込みも拒否する" do
    @order.update!(status: :consumed, consumed_at: Time.current)
    comment = DrinkOrders::ConsumptionCommentService.new(drink_order: @order).call!
    assert_raises(ActiveRecord::RecordNotUnique) do
      Comment.transaction(requires_new: true) { comment.dup.save!(validate: false) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Comment.transaction(requires_new: true) { comment.update_columns(drink_order_id: -1) }
    end
    assert_nil @session.comments.create!(booth: @booth, user: @customer, body: "normal").drink_order_id
  end

  test "H02 未消化・返却済み注文の消化通知を生成しない" do
    [ :pending, :refunded ].each do |status|
      @order.update!(status: status)
      assert_raises(DrinkOrders::ConsumeService::InvalidStatusError) do
        DrinkOrders::ConsumptionCommentService.new(drink_order: @order).call!
      end
    end
    assert_empty @session.comments
  end
end
