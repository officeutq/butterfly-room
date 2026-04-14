require "test_helper"

class CommentTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Test Store")
    @cast = User.create!(email: "cast_comment_model@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "customer_comment_model@example.com", password: "password", role: :customer)

    @booth = Booth.create!(
      store: @store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/comment-model"
    )

    BoothCast.create!(booth: @booth, cast_user: @cast)

    @stream_session = StreamSessions::StartService.new(booth: @booth, actor: @cast).call
    @booth.update!(status: :live)
  end

  test "chat は body 必須" do
    comment = Comment.new(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: nil,
      metadata: {}
    )

    assert_not comment.valid?
    assert_includes comment.errors.details[:body], { error: :blank }
  end

  test "event 系 kind は body なしでも有効" do
    comment = Comment.new(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_DRINK,
      body: nil,
      metadata: {}
    )

    assert comment.valid?
  end

  test "kind 未指定時は chat 扱いになる" do
    comment = Comment.new(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      body: "hello",
      metadata: {}
    )

    assert comment.valid?
    assert_equal Comment::KIND_CHAT, comment.kind
  end

  test "metadata 未指定時は空 hash になる" do
    comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "hello",
      metadata: nil
    )

    assert_equal({}, comment.metadata)
  end

  test "許可されていない kind は無効" do
    comment = Comment.new(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: "unknown",
      body: "hello",
      metadata: {}
    )

    assert_not comment.valid?
    assert comment.errors.details[:kind].any? { |detail| detail[:error] == :inclusion }
  end
end
