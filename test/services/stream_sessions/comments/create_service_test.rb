require "test_helper"

class StreamSessions::Comments::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Test Store")
    @cast = User.create!(email: "cast_comment_service@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "customer_comment_service@example.com", password: "password", role: :customer)

    @booth = Booth.create!(
      store: @store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/comment-service"
    )

    BoothCast.create!(booth: @booth, cast_user: @cast)

    @stream_session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.reload
    @booth.update!(status: :live)
    @stream_session = StreamSession.find(@stream_session.id)
  end

  test "従来どおり chat コメントを作成できる" do
    comment = nil

    without_comment_broadcast do
      assert_difference "Comment.count", 1 do
        comment = StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer,
          body: " hello "
        ).call
      end
    end

    assert_equal Comment::KIND_CHAT, comment.kind
    assert_equal "hello", comment.body
    assert_equal({}, comment.metadata)
  end

  test "chat は body が空だと invalid" do
    without_comment_broadcast do
      assert_raises(ActiveRecord::RecordInvalid) do
        StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer,
          body: "   "
        ).call
      end
    end
  end

  test "drink は body なしでも作成できる" do
    comment = nil

    without_comment_broadcast do
      assert_difference "Comment.count", 1 do
        comment = StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer,
          kind: Comment::KIND_DRINK,
          metadata: { "drink_item_id" => 123 }
        ).call
      end
    end

    assert_equal Comment::KIND_DRINK, comment.kind
    assert_nil comment.body
    assert_equal({ "drink_item_id" => 123 }, comment.metadata)
  end

  test "metadata が nil でも空 hash で作成される" do
    comment = nil

    without_comment_broadcast do
      comment = StreamSessions::Comments::CreateService.new(
        stream_session: @stream_session,
        user: @customer,
        body: "hello",
        metadata: nil
      ).call
    end

    assert_equal({}, comment.metadata)
  end

  test "配信中でないと作成できない" do
    @booth.update!(status: :standby)

    without_comment_broadcast do
      assert_raises(StreamSessions::Comments::CreateService::BoothNotLiveError) do
        StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer,
          body: "hello"
        ).call
      end
    end
  end

  test "chat は rate limit 対象" do
    without_comment_broadcast do
      StreamSessions::Comments::CreateService.new(
        stream_session: @stream_session,
        user: @customer,
        body: "first"
      ).call

      assert_raises(StreamSessions::Comments::CreateService::RateLimitedError) do
        StreamSessions::Comments::CreateService.new(
          stream_session: @stream_session,
          user: @customer,
          body: "second"
        ).call
      end
    end
  end

  private

  def without_comment_broadcast
    notifier_class = CommentNotifier.singleton_class
    original_method = CommentNotifier.method(:append) if CommentNotifier.respond_to?(:append)

    notifier_class.send(:define_method, :append) do |_comment|
      nil
    end

    yield
  ensure
    if original_method
      notifier_class.send(:define_method, :append, original_method)
    else
      notifier_class.send(:remove_method, :append)
    end
  end
end
