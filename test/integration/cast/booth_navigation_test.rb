# frozen_string_literal: true

require "test_helper"

class Cast::BoothNavigationTest < ActionDispatch::IntegrationTest
  %i[cast store_admin system_admin].each do |role|
    test "#{role}: direct URLs preserve selection and old forms cannot update another booth" do
      prepare_operator(role)
      ended_session(@a, "History A")
      ended_session(@b, "History B")
      select_booth(@a)
      assert_no_stream_change do
        [ cast_booth_path(@b), edit_cast_booth_path(@b), cast_booth_stream_sessions_path(@b) ].each do |path|
          get path
          assert_response :conflict
          assert_selection(@a)
          assert_includes response.body, "対象のブースをヘッダーから選択してください"
        end
        select_booth(@b)
        get cast_booth_stream_sessions_path(@b)
        assert_response :success
        assert_includes response.body, "History B"
        assert_not_includes response.body, "History A"
        get edit_cast_booth_path(@b)
        assert_select ".booth-form__back[href='#{cast_booth_path(@b)}']"
        select_booth(@a)
        patch cast_booth_path(@b), params: { booth: { name: "Updated B" } }, as: :json
        assert_response :conflict
        assert_selection(@a)
        assert_equal "Booth B", @b.reload.name
        select_booth(@b)
        patch cast_booth_path(@b), params: { booth: { name: "Updated B" } }
        assert_redirected_to cast_booth_path(@b)
        assert_equal "Updated B", @b.reload.name
      end
      get dashboard_path
      assert_select ".card-title", text: "ブース情報", count: 1
      assert_select ".card-title", text: "ブース編集", count: 0
      assert_select ".card-title", text: "配信履歴", count: 0
    end

    test "#{role}: archived history remains readable without changing selection" do
      prepare_operator(role)
      ended_session(@b, "Archived History B")
      @b.update!(archived_at: Time.current)
      select_booth(@a)
      if role == :cast
        get cast_booth_path(@b)
        assert_response :success
      else
        select_booth(@b)
        get cast_booth_path(@b)
        assert_response :success
      end
      get cast_booth_stream_sessions_path(@b)
      assert_response :success
      assert_includes response.body, "Archived History B"
      assert_select "a[href=?]", cast_booth_path(@b), text: "ブース情報へ戻る"
      get cast_booth_path(@b)
      assert_response :success
      assert_selection(role == :cast ? @a : @b)
      get edit_cast_booth_path(@b)
      assert_response :not_found
      assert_selection(role == :cast ? @a : @b)
    end

    test "#{role}: missing and unauthorized history never falls back to the selected booth" do
      prepare_operator(role)
      select_booth(@a)
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
            assert_redirected_to path
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

  test "information links stay on the selected booth and cannot prefetch another selection" do
    prepare_operator(:cast)
    select_booth(@a)
    get cast_booth_path(@a)
    assert_navigation_confirmation(expected: false, booth: @a)
    get edit_cast_booth_path(@b), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_selection(@a)
    assert_equal "Booth B", @b.reload.name
  end

  test "multiple candidate selection preserves its information destination without a stream" do
    prepare_operator(:cast)
    get dashboard_path
    assert_select "a[href='#{select_modal_cast_booths_path(return_to_key: 'booth_show')}'][data-turbo-prefetch='false']"
    get select_modal_cast_booths_path(return_to_key: "booth_show"), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "form input[name='return_to_key'][value='booth_show']", count: 2
    get cast_booths_path(return_to_key: "booth_show")
    assert_redirected_to dashboard_path
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
      get select_modal_cast_booths_path(return_to_key: "booth_show"), headers: { "Turbo-Frame" => "modal" }
      assert_response :success
      assert_nil @request.session[:current_booth_id]
      select_booth(@b)
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
      assert_select "[data-redirect-url='#{dashboard_path}']"
      assert_includes flash[:alert], "操作可能なブースがありません"
      assert_nil @request.session[:current_booth_id]
      post cast_current_booth_path, params: { booth_id: @b.id, return_to_key: "booth_show" }
      assert_response :conflict
      assert_nil @request.session[:current_booth_id]
    end
  end

  private

  def select_booth(booth)
    post cast_current_booth_path, params: { booth_id: booth.id, return_to_key: "booth_show" }
    assert_redirected_to cast_booth_path(booth)
  end

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
