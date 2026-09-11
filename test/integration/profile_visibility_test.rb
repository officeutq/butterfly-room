# frozen_string_literal: true

require "test_helper"

class ProfileVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @cast = create_user(:cast, "cast")
    @customer = create_user(:customer, "customer")
    @admin = create_user(:store_admin, "admin")
    @empty_admin = create_user(:store_admin, "empty-admin")
    @support_admin = create_user(:store_admin, "support-admin")
    @operator = create_user(:system_admin, "operator")
    @deleted = create_user(:cast, "deleted", deleted_at: Time.current)
    @store = Store.create!(name: "Profile Public Store", published: true)
    Booth.create!(store: @store, name: "Profile Offline Booth", status: :offline)
    @support = Store.create!(name: "Profile Support Store", sales_support_company: true)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    StoreMembership.create!(store: @store, user: @support_admin, membership_role: :admin)
    StoreMembership.create!(store: @support, user: @support_admin, membership_role: :admin)
    @targets = [ @cast, @customer, @admin, @empty_admin, @support_admin, @operator, @deleted ]
    @member_targets = [ @cast, @customer, @admin, @empty_admin ]
  end

  test "guest and every signed in role follow the profile matrix including self and SEO" do
    @targets.each { |target| assert_profile(target, allowed: target == @cast) }

    @targets.reject(&:deleted?).each do |viewer|
      sign_in viewer
      @targets.each do |target|
        allowed = !target.deleted? && (@member_targets.include?(target) || target == viewer)
        assert_profile(target, allowed: allowed)
      end
      sign_out viewer
    end

    assert_not User.profiles_visible_to(@deleted).exists?(@deleted.id)
    sign_in @deleted
    get user_path(@deleted)
    assert_redirected_to new_user_session_path
  end

  test "store publication and booths do not control member profiles but related stores stay public" do
    sign_in @customer
    @store.update!(published: false)
    get user_path(@admin)
    assert_response :success
    assert_not_includes response.body, @store.name
    @store.update!(published: true)
    @store.booths.update_all(archived_at: Time.current)
    get user_path(@admin)
    assert_response :success
    assert_includes response.body, @store.name
  end

  test "edit action is visible only on the signed in users own profile" do
    get user_path(@cast)
    assert_select ".user-show-edit", count: 0

    @targets.reject(&:deleted?).each do |viewer|
      sign_in viewer
      get user_path(viewer)
      assert_response :success
      assert_select ".user-show-header a.user-show-edit[href='#{edit_profile_path}'].btn-outline-secondary.btn-sm", count: 1 do
        assert_select "i.bi-pencil[aria-hidden='true']"
        assert_select "span", text: "プロフィールを編集"
      end

      other = viewer == @cast ? @customer : @cast
      get user_path(other)
      assert_response :success
      assert_select ".user-show-edit", count: 0
      sign_out viewer
    end
  end

  test "all active roles can complete profile editing at their own detail" do
    @targets.reject(&:deleted?).each do |viewer|
      sign_in viewer
      patch profile_path, params: { user: { display_name: viewer.display_name, bio: viewer.bio } }
      assert_redirected_to user_path(viewer)
      follow_redirect!
      assert_response :success
      assert_select ".user-show-edit", count: 1

      patch profile_path, params: { user: { display_name: viewer.display_name } }, as: :json
      assert_response :success
      assert_equal user_path(viewer), response.parsed_body.fetch("redirect_url")
      sign_out viewer
    end
  end

  test "support membership and role changes are evaluated on each request" do
    sign_in @customer
    membership = StoreMembership.create!(store: @support, user: @admin, membership_role: :cast)
    assert_profile(@admin, allowed: true)
    membership.update!(membership_role: :admin)
    assert_profile(@admin, allowed: false)
    membership.destroy!
    assert_profile(@admin, allowed: true)
    @admin.update!(role: :system_admin)
    assert_profile(@admin, allowed: false)
    @admin.update!(role: :cast)
    assert_profile(@admin, allowed: true)
    @admin.update!(deleted_at: Time.current)
    assert_profile(@admin, allowed: false)
  end

  test "favorite listing and registration follow the matrix for every viewer including self" do
    @targets.reject(&:deleted?).each do |viewer|
      sign_in viewer
      @targets.each do |target|
        allowed = !target.deleted? && (@member_targets.include?(target) || target == viewer)
        assert_difference("viewer.favorite_users.count", allowed ? 1 : 0) do
          post user_favorite_path(target), headers: turbo_headers
        end
        assert_response allowed ? :success : :not_found
        # 過去に登録済みだった非公開・退会対象も一覧から除外する。
        viewer.favorite_users.find_or_create_by!(target_user: target)
      end
      get favorites_users_path
      assert_response :success
      @targets.each do |target|
        allowed = !target.deleted? && (@member_targets.include?(target) || target == viewer)
        assert_select ".users-card-name-link[href=?]", user_path(target), count: allowed ? 1 : 0
      end
      sign_out viewer
    end
  end

  test "favorites retain hidden records and search reevaluates membership and deletion" do
    sign_in @customer
    favorite = @customer.favorite_users.create!(target_user: @admin)
    get favorites_users_path, params: { q: @admin.display_name }
    assert_select ".users-card-name-link[href=?]", user_path(@admin), count: 1
    membership = StoreMembership.create!(store: @support, user: @admin, membership_role: :admin)
    get favorites_users_path, params: { q: @admin.display_name }
    assert_select ".users-card", count: 0
    assert FavoriteUser.exists?(favorite.id)
    membership.destroy!
    get favorites_users_path, params: { q: @admin.display_name }
    assert_select ".users-card-name-link[href=?]", user_path(@admin), count: 1
    @admin.update!(deleted_at: Time.current)
    get favorites_users_path
    assert_select ".users-card", count: 0
    assert FavoriteUser.exists?(favorite.id)
  end

  test "hidden favorites can be removed without rendering private data or touching another users favorites" do
    sign_in @customer
    [ @support_admin, @operator, @deleted ].each do |target|
      own = @customer.favorite_users.create!(target_user: target)
      other = @cast.favorite_users.create!(target_user: target)
      delete user_favorite_path(target), headers: turbo_headers
      assert_response :no_content
      assert_empty response.body
      assert_not FavoriteUser.exists?(own.id)
      assert FavoriteUser.exists?(other.id)
      delete user_favorite_path(target), headers: turbo_headers
      assert_response :no_content
    end
    delete user_favorite_path(@support_admin)
    assert_redirected_to favorites_users_path
  end

  test "guest favorite operations require login and missing targets do not register" do
    get favorites_users_path
    assert_redirected_to new_user_session_path
    assert_no_difference "FavoriteUser.count" do
      post user_favorite_path(@cast)
      assert_redirected_to new_user_session_path
      delete user_favorite_path(@cast)
      assert_redirected_to new_user_session_path
    end
    sign_in @customer
    get root_path
    assert_response :success
    get user_path(id: 0)
    assert_response :not_found
    assert_no_difference "FavoriteUser.count" do
      post user_favorite_path(user_id: 0), headers: turbo_headers
    end
    assert_response :not_found
  end

  test "favorite ordering phrase search and idempotent toggle stay unchanged" do
    sign_in @customer
    @cast.update!(display_name: "Tokyo Night")
    @admin.update!(display_name: "Tokyo", bio: "Night")
    @customer.favorite_users.create!(target_user: @cast, created_at: 2.days.ago)
    @customer.favorite_users.create!(target_user: @admin, created_at: 1.day.ago)
    get favorites_users_path
    assert_equal [ user_path(@admin), user_path(@cast) ], css_select(".users-card-name-link").map { |a| a["href"] }
    get favorites_users_path, params: { q: "Tokyo Night" }
    assert_select ".users-card-name-link[href=?]", user_path(@cast), count: 1
    assert_select ".users-card-name-link[href=?]", user_path(@admin), count: 0
    assert_no_difference "FavoriteUser.count" do
      post user_favorite_path(@cast), headers: turbo_headers
    end
    assert_response :success
    assert_difference "FavoriteUser.count", -1 do
      delete user_favorite_path(@cast), headers: turbo_headers
    end
    assert_response :success
    assert_select "turbo-stream[action='replace']", count: 2
  end

  test "home keeps thirty results and AND search while favorites have no thirty result cap" do
    casts = 31.times.map { |i| create_user(:cast, "Limit #{i}") }
    casts.each { |cast| @customer.favorite_users.create!(target_user: cast) }
    get root_path, params: { mode: "users", q: "Matrix Limit" }
    assert_response :success
    assert_equal casts.last(30).reverse.map { |cast| user_path(cast) },
                 css_select(".users-card-name-link").map { |a| a["href"] }

    casts.first.update!(display_name: "Tokyo", bio: "Night")
    get root_path, params: { mode: "users", q: "Tokyo　Night" }
    assert_select ".users-card-name-link[href=?]", user_path(casts.first), count: 1

    sign_in @customer
    get favorites_users_path
    assert_response :success
    assert_select ".users-card", count: 31
  end

  private

  def create_user(role, name, **attributes)
    User.create!(email: "profile-matrix-#{name.tr(" ", "-")}@example.com", password: "password",
                 role: role, display_name: "Matrix #{name}", bio: "Bio #{name}", **attributes)
  end

  def assert_profile(target, allowed:)
    get user_path(target)
    assert_response allowed ? :success : :not_found
    if allowed
      assert_select "h1", text: target.display_name
      robots = css_select("meta[name='robots']").map { |meta| meta["content"] }.join
      if target.cast?
        assert_not_includes robots, "noindex"
      else
        assert_includes robots, "noindex"
        assert_includes robots, "nofollow"
      end
    else
      assert_not_includes response.body, target.bio
    end
  end

  def turbo_headers
    { "Accept" => "text/vnd.turbo-stream.html" }
  end
end
