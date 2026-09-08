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

  test "all author roles and comment kinds obey guest and member rules on append and replace" do
    support = Store.create!(name: "Comment Support", sales_support_company: true)
    authors = %i[cast customer store_admin system_admin].map do |role|
      User.create!(email: "comment-matrix-#{role}@example.com", password: "password",
                   role: role, display_name: "Author #{role}")
    end
    support_admin = User.create!(email: "comment-matrix-support@example.com", password: "password",
                                role: :store_admin, display_name: "Support Author")
    StoreMembership.create!(store: support, user: support_admin, membership_role: :admin)
    deleted = User.create!(email: "comment-matrix-deleted@example.com", password: "password",
                          role: :cast, display_name: "Deleted Author", deleted_at: Time.current)

    (authors + [ support_admin, deleted ]).each do |author|
      @comment.user = author
      member_visible = authors.include?(author) && !author.system_admin?
      Comment::KINDS.each do |kind|
        @comment.update!(kind: kind, body: "Comment matrix body", metadata: {})
        %i[append replace].each do |operation|
          member_messages = nil
          guest_messages = capture_broadcasts(guest_stream_name) do
            member_messages = capture_broadcasts(member_stream_name) do
              CommentNotifier.public_send(operation, @comment)
            end
          end
          guest = Nokogiri::HTML.fragment(guest_messages.fetch(0))
          assert_empty guest.css(".comment-author a, [data-controller='self-profile-link']")
          assert_includes guest.text, author.display_name
          member = Nokogiri::HTML.fragment(member_messages.fetch(0))
          assert_equal member_visible ? 1 : 0, member.css(".comment-author a").size
          self_only = !member_visible && !author.deleted?
          assert_equal self_only ? 1 : 0, member.css("[data-controller='self-profile-link']").size
          assert_includes member.text, author.display_name
        end
      end
    end
  end

  test "hidden author has no profile link or self exception until the comment is restored" do
    @comment.user.update!(role: :system_admin)
    @comment.update!(metadata: { "hidden" => true })
    html = capture_broadcasts(member_stream_name) { CommentNotifier.replace(@comment) }.first
    assert_empty Nokogiri::HTML.fragment(html).css(".comment-author a, [data-controller='self-profile-link']")
    @comment.update!(metadata: {})
    html = capture_broadcasts(member_stream_name) { CommentNotifier.replace(@comment) }.first
    assert_equal 1, Nokogiri::HTML.fragment(html).css("[data-controller='self-profile-link']").size
  end

  test "initial collection batches profile eligibility and matches broadcast author markup" do
    @comment.user.update!(role: :store_admin)
    comments = 5.times.map do |i|
      Comment.create!(stream_session: @stream_session, booth: @comment.booth,
                      user: @comment.user, body: "Batch #{i}")
    end
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) do
      queries << payload[:sql] if payload[:sql].include?("sales_support_company")
    end
    html = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      html = ApplicationController.render(partial: "booths/comment_section", locals: {
        stream_session: @stream_session, comments: comments, authenticated_viewer: true
      })
    end
    assert_equal 1, queries.size
    assert_equal 5, Nokogiri::HTML.fragment(html).css(".comment-author a").size

    @comment.user.update!(role: :system_admin)
    html = ApplicationController.render(partial: "booths/comment_section", locals: {
      stream_session: @stream_session, comments: comments, authenticated_viewer: true
    })
    fragment = Nokogiri::HTML.fragment(html)
    assert_empty fragment.css(".comment-author a")
    assert_equal 5, fragment.css("[data-controller='self-profile-link']").size
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end

  def member_stream_name
    Turbo::StreamsChannel.send(:stream_name_from, [ @stream_session, :comments ])
  end

  def guest_stream_name
    Turbo::StreamsChannel.send(
      :stream_name_from,
      [ @stream_session, :comments, :guest ]
    )
  end
end
