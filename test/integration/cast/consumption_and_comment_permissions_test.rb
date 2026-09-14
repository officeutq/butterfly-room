require "test_helper"
require_relative "../../support/consumption_test_support"

class Cast::ConsumptionAndCommentPermissionsTest < ActionDispatch::IntegrationTest
  include ConsumptionTestSupport
  setup { build_consumption_fixture }

  test "H02 店舗無関係のキャストと管理者の消化API直送を403にする" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      before = financial_snapshot
      [ @creator, @assigned, @outsider, @admin, @system ].each do |user|
        sign_in user, scope: :user
        post consume_cast_drink_order_path(@order), as: :json
        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["error"]
        assert_equal before, financial_snapshot
      end
    end
  end

  test "H02 本人の消化成功後に同じ要求が再送されても重複計上しない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @publisher, scope: :user
      post consume_cast_drink_order_path(@order), as: :json
      assert_response :ok
      before = financial_snapshot
      post consume_cast_drink_order_path(@order), as: :json
      assert_response :conflict
      assert_equal "not_pending", response.parsed_body["error"]
      assert_equal before, financial_snapshot
    end
  end

  test "H02 非表示と解除はY本人だけに許可し操作履歴の実行者もYとする" do
    comment = Comment.create!(stream_session: @session, booth: @booth, user: @customer, body: "chat")
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @publisher, scope: :user
      patch hide_stream_session_comment_path(@session, comment)
      assert_response :ok
      assert comment.reload.hidden?
      assert_equal @publisher.id, comment.metadata["hidden_by_user_id"]
      before = comment.attributes
      [ @creator, @assigned, @outsider, @admin, @system, @customer ].each do |user|
        sign_in user, scope: :user
        patch unhide_stream_session_comment_path(@session, comment)
        assert_response :forbidden
        assert_equal before, comment.reload.attributes
      end
      sign_in @publisher, scope: :user
      patch unhide_stream_session_comment_path(@session, comment)
      assert_response :ok
      refute comment.reload.hidden?
      assert_equal @customer.id, comment.user_id
    end
  end

  test "H04 終了済みコメントは保存済みYで判定し不明なら誰にも本人権限を与えない" do
    comment = Comment.create!(stream_session: @session, booth: @booth, user: @customer, body: "past")
    @session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session_id: nil)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @publisher, scope: :user
      patch hide_stream_session_comment_path(@session, comment)
      assert_response :ok
      @session.update!(actual_publisher_user: nil, actual_publisher_source: nil, actual_publisher_recorded_at: nil)
      patch unhide_stream_session_comment_path(@session, comment)
      assert_response :forbidden
      sign_in @creator, scope: :user
      patch unhide_stream_session_comment_path(@session, comment)
      assert_response :forbidden
    end
  end

  test "H02 HTTP投稿で人物とkindと不明フラグは指定できず通常投稿者を保つ" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @customer, scope: :user
      post stream_session_comments_path(@session), params: {
        comment: { body: "ordinary", user_id: @publisher.id, kind: "drink_consumed", metadata: { publisher_unknown: true } }
      }, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      comment = @session.comments.sole
      assert_equal @customer.id, comment.user_id
      assert_equal "chat", comment.kind
      assert_equal({}, comment.metadata)
    end
  end

  test "H02 初期表示と共有更新は本人IDを持ちXを配信者として強調しない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      [ @creator, @publisher ].each do |user|
        comment = Comment.create!(stream_session: @session, booth: @booth, user: user, body: "render")
        html = ApplicationController.render(partial: "comments/comment", locals: { comment: comment })
        fragment = Nokogiri::HTML.fragment(html)
        assert_equal user == @publisher ? 1 : 0, fragment.css(".comment-from-broadcaster").size
        assert_equal @publisher.id.to_s, fragment.at_css(".comment-actions")["data-comment-actions-publisher-id-value"]
      end
      html = ApplicationController.render(partial: "cast/stream_sessions/pending_drink_orders", locals: { stream_session: @session })
      fragment = Nokogiri::HTML.fragment(html)
      assert_equal @publisher.id.to_s, fragment.at_css("[data-controller='drink-consume']")["data-drink-consume-publisher-id-value"]
      assert fragment.at_css("[data-drink-consume-target='operation']").key?("hidden")
    end
  end

  test "H02 通報者と投稿者は実配信者に置換せず非表示コメントの通報も維持する" do
    comment = Comment.create!(stream_session: @session, booth: @booth, user: @outsider,
      body: "report", metadata: { hidden: true })
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      sign_in @publisher, scope: :user
      post report_stream_session_comment_path(@session, comment), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      report = comment.comment_reports.sole
      assert_equal @publisher.id, report.reporter_user_id
      assert_equal @outsider.id, report.reported_user_id
      assert_equal @outsider.id, comment.reload.user_id
    end
  end
end
