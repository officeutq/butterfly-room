# frozen_string_literal: true

require "test_helper"

class Cast::BoothNavigationTest < ActionDispatch::IntegrationTest
  %i[cast store_admin system_admin].each do |role|
    test "#{role}: information preserves selection while history and edit select the URL target" do
      prepare_operator(role)
      ended_session(@a, "History A")
      ended_session(@b, "History B")
      get edit_cast_booth_path(@a)

      assert_no_stream_change do
        get cast_booth_path(@b)
        assert_response :success
        assert_selection(@a)
        get cast_booth_stream_sessions_path(@b)
        assert_response :success
        assert_selection(@b)
        assert_select "h1", text: @b.name
        assert_includes response.body, "History B"
        assert_not_includes response.body, "History A"
        assert_select "a[href='#{cast_booth_path(@b)}']", text: "ブース情報へ戻る"

        get edit_cast_booth_path(@b)
        assert_select ".booth-form__back[href='#{cast_booth_path(@b)}']"
        # 別タブでAを選んだ後も、BのフォームはBだけを保存する。
        get edit_cast_booth_path(@a)
        patch cast_booth_path(@b), params: { booth: { name: "Updated B" } }
        assert_redirected_to cast_booth_path(@b)
        assert_selection(@b)
        assert_equal "Updated B", @b.reload.name
        assert_equal "Booth A", @a.reload.name
      end

      get dashboard_path
      assert_select ".card-title", text: "ブース情報", count: 1
      assert_select ".card-title", text: "ブース編集", count: 0
      assert_select ".card-title", text: "配信履歴", count: 0
      assert_select "a[href='#{cast_booth_path(@b)}'] .card-text", text: "ブース情報の確認・編集、配信履歴の確認、URLの共有を行います"
    end

    test "#{role}: archived history remains readable without changing selection" do
      prepare_operator(role)
      ended_session(@b, "Archived History B")
      @b.update!(archived_at: Time.current)
      get edit_cast_booth_path(@a)

      get cast_booth_path(@b)
      assert_response :success
      assert_select ".booth-show-actions a", count: 0
      assert_select ".booth-show-actions button[disabled]", count: 0
      assert_select "button[data-bs-target='#booth-share-modal']", count: 1
      get cast_booth_stream_sessions_path(@b)
      assert_response :success
      assert_includes response.body, "Archived History B"
      assert_selection(@a)
      get edit_cast_booth_path(@b)
      assert_response :not_found
      assert_selection(@a)
    end

    test "#{role}: missing and unauthorized history never falls back to the selected booth" do
      prepare_operator(role)
      get edit_cast_booth_path(@a)
      get cast_booth_stream_sessions_path(booth_id: 0)
      assert_response :not_found
      assert_selection(@a)
      unless role == :system_admin
        outsider = Booth.create!(store: Store.create!(name: "Other store"), name: "Private booth")
        get cast_booth_stream_sessions_path(outsider)
        assert_response :forbidden
        assert_selection(@a)
        assert_not_includes response.body, "Private booth"
      end
    end

    test "#{role}: information selection by key and legacy URL never starts a stream" do
      prepare_operator(role)
      destinations.each do |key, path|
        [ { return_to_key: key }, { return_to: "#{path}?from=legacy" } ].each do |destination|
          assert_no_stream_change do
            post cast_current_booth_path, params: { booth_id: @b.id, **destination }
            assert_redirected_to destination[:return_to] || path
            assert_selection(@b)
          end
        end
      end

      @a.update!(archived_at: Time.current)
      destinations.each do |key, path|
        assert_no_stream_change do
          get select_modal_cast_booths_path(return_to_key: key)
          assert_redirected_to path
          assert_selection(@b)
          get select_modal_cast_booths_path(return_to: path), headers: { "Turbo-Frame" => "modal" }
          assert_response :success
          assert_select "[data-redirect-url='#{path}']", count: 1
        end
      end
    end
  end

  test "links confirm only switching from an explicitly selected live or away booth" do
    prepare_operator(:cast)
    @a.update!(status: :live)
    get cast_booth_path(@b)
    assert_navigation_confirmation(expected: false)

    %i[live away standby offline].each do |status|
      @a.update!(status:)
      get edit_cast_booth_path(@a)
      get cast_booth_path(@b)
      assert_navigation_confirmation(expected: %i[live away].include?(status))
      get cast_booth_path(@a)
      assert_navigation_confirmation(expected: false, booth: @a)
    end

    @a.update!(status: :live)
    get cast_booths_path
    assert_select "a[href='#{edit_cast_booth_path(@b)}'][data-controller='confirm-navigation'][data-turbo-prefetch='false']"
  end

  test "multiple candidate selection preserves its information destination without a stream" do
    prepare_operator(:cast)
    get dashboard_path
    assert_select "a[href='#{select_modal_cast_booths_path(return_to_key: 'booth_show')}'][data-turbo-prefetch='false']"
    get select_modal_cast_booths_path(return_to_key: "booth_show"), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "form input[name='return_to_key'][value='booth_show']", count: 2
    get cast_booths_path(return_to_key: "booth_show")
    assert_select "form input[name='return_to_key'][value='booth_show']", count: 2
    assert_no_stream_change do
      post cast_current_booth_path, params: { booth_id: @b.id, return_to_key: "booth_show" }
      assert_redirected_to cast_booth_path(@b)
    end
  end

  test "a live booth used by another operator can be selected for information without changing the stream" do
    prepare_operator(:store_admin)
    starter = User.create!(email: "navigation-starter@example.com", password: "password", role: :cast)
    stream = StreamSession.create!(booth: @b, store: @b.store, started_by_cast_user: starter, status: :live, started_at: Time.current)
    @b.update!(status: :live, current_stream_session: stream)
    assert_no_stream_change do
      get select_modal_cast_booths_path(return_to_key: "booth_show")
      assert_redirected_to cast_booth_path(@b)
      assert_selection(@b)
    end
  end

  test "zero active candidates and archived targets do not become a selection" do
    prepare_operator(:cast)
    @a.update!(archived_at: Time.current)
    @b.update!(archived_at: Time.current)
    assert_no_stream_change do
      get select_modal_cast_booths_path(return_to_key: "booth_show", archived: 1), headers: { "Turbo-Frame" => "modal" }
      assert_response :success
      assert_select ".alert", text: "操作可能なブースがありません。"
      assert_nil @request.session[:current_booth_id]
      post cast_current_booth_path, params: { booth_id: @b.id, return_to_key: "booth_show" }
      assert_redirected_to cast_booths_path
      assert_nil @request.session[:current_booth_id]
    end
  end

  private

  def prepare_operator(role)
    @actor = User.create!(email: "navigation-#{role}@example.com", password: "password", role:)
    @a = Booth.create!(store: Store.create!(name: "Store A"), name: "Booth A")
    @b = Booth.create!(store: Store.create!(name: "Store B"), name: "Booth B")
    [ @a, @b ].each do |booth|
      if role == :cast
        BoothCast.create!(booth:, cast_user: @actor)
      elsif role == :store_admin
        StoreMembership.create!(store: booth.store, user: @actor, membership_role: :admin)
      end
    end
    sign_in @actor, scope: :user
  end

  def ended_session(booth, title)
    StreamSession.create!(booth:, store: booth.store, started_by_cast_user: @actor,
                          title:, status: :ended, started_at: 1.hour.ago, ended_at: Time.current)
  end

  def assert_selection(booth)
    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal booth.store_id, @request.session[:current_store_id]
  end

  def assert_no_stream_change
    before = Booth.order(:id).pluck(:id, :status, :current_stream_session_id, :ivs_stage_arn)
    assert_no_difference "StreamSession.count" do
      yield
    end
    assert_equal before, Booth.order(:id).pluck(:id, :status, :current_stream_session_id, :ivs_stage_arn)
  end

  def destinations
    { "booth_show" => cast_booth_path(@b), "booth_edit" => edit_cast_booth_path(@b),
      "booth_stream_sessions" => cast_booth_stream_sessions_path(@b) }
  end

  def assert_navigation_confirmation(expected:, booth: @b)
    [ edit_cast_booth_path(booth), cast_booth_stream_sessions_path(booth) ].each do |path|
      assert_select "a[href='#{path}'][data-turbo-prefetch='false']", count: 1
      assert_select "a[href='#{path}'][data-controller='confirm-navigation']", count: expected ? 1 : 0
    end
  end
end
