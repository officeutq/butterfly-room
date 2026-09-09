# frozen_string_literal: true

require "test_helper"

class Admin::StoreEditReturnTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "詳細から編集する店舗", published: true)
    @admin = User.create!(email: "store-edit-return@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user
  end

  test "detail entry carries its return destination through the form without switching the selected store" do
    selected_store = Store.create!(name: "選択中の店舗")
    StoreMembership.create!(store: selected_store, user: @admin, membership_role: :admin)
    post admin_current_store_path, params: { store_id: selected_store.id }

    get edit_admin_store_path(@store, return_to: "store_detail")

    assert_response :success
    assert_select "a.store-edit__back[href=?]", store_path(@store), count: 1
    assert_select "form#store-edit-form[action=?]", admin_store_path(@store) do
      assert_select "input[type=hidden][name=return_to][value=store_detail]", count: 1
    end
    assert_equal selected_store.id, @request.session[:current_store_id].to_i

    patch admin_store_path(@store), params: { return_to: "store_detail", store: { description: "更新後" } }, as: :json

    assert_response :success
    assert_equal store_path(@store), response.parsed_body["redirect_url"]
    assert_equal selected_store.id, @request.session[:current_store_id].to_i
    assert_equal "更新後", @store.reload.description
    assert_nil selected_store.reload.description
  end

  [ :html, :json ].each do |format|
    test "#{format} detail save returns to the saved store" do
      save_store(format, return_to: "store_detail", store: { description: "変更済み" })

      assert_saved_return(format, store_path(@store))
      assert_equal "変更済み", @store.reload.description
    end

    test "#{format} unpublishing through detail returns to the dashboard" do
      save_store(format, return_to: "store_detail", store: { published: false })

      assert_saved_return(format, dashboard_path)
      assert_not @store.reload.published?
    end

    test "#{format} saves from existing entries keep the dashboard destination" do
      save_store(format, store: { description: "既存入口" })

      assert_saved_return(format, dashboard_path)
    end
  end

  test "unpublished stores use the dashboard back link even with a detail entry marker" do
    @store.update!(published: false)

    get edit_admin_store_path(@store, return_to: "store_detail")

    assert_response :success
    assert_select "a.store-edit__back[href=?]", dashboard_path, count: 1
  end

  test "unrecognized or structured return destinations are ignored on edit and save" do
    [ nil, "unknown", "https://example.com/", "//example.com/", store_path(@store),
      [ "store_detail" ], { path: "store_detail" } ].each do |destination|
      get edit_admin_store_path(@store), params: { return_to: destination }

      assert_response :success
      assert_select "a.store-edit__back[href=?]", dashboard_path, count: 1
      assert_select "input[name=return_to]", count: 0

      save_store(:json, return_to: destination, store: { description: "許可済みの保存" })

      assert_saved_return(:json, dashboard_path)
    end
  end

  test "failed JSON save leaves the store unchanged and retry can still return to detail" do
    save_store(:json, return_to: "store_detail", store: { name: "", description: "保存されない" })

    assert_response :unprocessable_entity
    assert_equal "store_update_invalid", response.parsed_body["error"]
    assert_not response.parsed_body.key?("redirect_url")
    assert_equal "詳細から編集する店舗", @store.reload.name

    save_store(:json, return_to: "store_detail", store: { name: "修正後" })

    assert_saved_return(:json, store_path(@store))
    assert_equal "修正後", @store.reload.name
  end

  test "failed HTML save preserves the detail entry marker when reopening the editor" do
    save_store(:html, return_to: "store_detail", store: { name: "" })

    assert_redirected_to edit_admin_store_path(@store, return_to: "store_detail")
    follow_redirect!
    assert_select "a.store-edit__back[href=?]", store_path(@store), count: 1
    assert_select "input[name=return_to][value=store_detail]", count: 1
  end

  test "detail entry never grants edit rights to another store" do
    other_store = Store.create!(name: "権限のない店舗", published: true)

    get edit_admin_store_path(other_store, return_to: "store_detail")
    assert_response :forbidden

    patch admin_store_path(other_store), params: { return_to: "store_detail", store: { name: "更新不可" } }, as: :json
    assert_response :forbidden
    assert_equal "権限のない店舗", other_store.reload.name
  end

  private

  def save_store(format, params)
    if format == :json
      patch admin_store_path(@store), params:, as: :json
    else
      patch admin_store_path(@store), params:
    end
  end

  def assert_saved_return(format, path)
    if format == :json
      assert_response :success
      assert_equal "complete", response.parsed_body["state"]
      assert_equal path, response.parsed_body["redirect_url"]
    else
      assert_redirected_to path
    end
  end
end
