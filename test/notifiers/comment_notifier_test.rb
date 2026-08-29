# frozen_string_literal: true

require "test_helper"

class CommentNotifierTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    store = Store.create!(name: "Comment Notifier Store", published: true)
    cast = User.create!(
      email: "comment-notifier-cast@example.com",
      password: "password",
      role: :cast
    )
    customer = User.create!(
      email: "comment-notifier-customer@example.com",
      password: "password",
      role: :customer
    )
    booth = Booth.create!(store: store, name: "Comment Notifier Booth", status: :live)
    @stream_session = StreamSession.create!(
      booth: booth,
      store: store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: cast,
      ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/commentNotifier"
    )
    booth.update!(current_stream_session: @stream_session)
    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: booth,
      user: customer,
      body: "未ログインへリアルタイム配信するコメント"
    )
  end

  test "append broadcasts a read-only comment to the guest stream" do
    messages = capture_broadcasts(guest_stream_name) do
      CommentNotifier.append(@comment)
    end

    assert_equal 1, messages.size
    html = messages.first
    assert_includes html, %(action="append")
    assert_includes html, %(target="comments")
    assert_includes html, "未ログインへリアルタイム配信するコメント"
    assert_includes html, routes.guest_auth_prompt_path
    assert_not_includes html, routes.report_stream_session_comment_path(@stream_session, @comment)
  end

  test "replace broadcasts a read-only update to the guest stream" do
    @comment.update!(metadata: { "hidden" => true })

    messages = capture_broadcasts(guest_stream_name) do
      CommentNotifier.replace(@comment)
    end

    assert_equal 1, messages.size
    html = messages.first
    assert_includes html, %(action="replace")
    assert_includes html, %(target="comment_#{@comment.id}")
    assert_includes html, "このコメントは非表示になっています"
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end

  def guest_stream_name
    Turbo::StreamsChannel.send(
      :stream_name_from,
      [ @stream_session, :comments, :guest ]
    )
  end
end
