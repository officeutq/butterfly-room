require "test_helper"

class AdminBoothsIndexTest < ActionDispatch::IntegrationTest
  %i[store_admin system_admin].each do |role|
    test "#{role}: 旧一覧は店舗未選択でも選択を要求せずダッシュボードへ戻す" do
      actor = User.create!(email: "old-index-#{role}@example.com", password: "password", role: role)
      sign_in actor
      [ 0, 1, 2 ].each do |count|
        if count.positive?
          store = Store.create!(name: "店舗#{count}")
          StoreMembership.create!(store: store, user: actor, membership_role: :admin)
          Booth.create!(store: store, name: "ブース#{count}", archived_at: count == 2 ? Time.current : nil)
        end
        [ admin_booths_path, admin_booths_path(archived: 1, return_to: cast_booths_path) ].each do |path|
          get path
          assert_redirected_to dashboard_path
          selection = [ @request.session[:current_store_id], @request.session[:current_booth_id] ]
          follow_redirect!
          assert_response :success
          assert_select ".admin-booths-card, turbo-frame#modal[src]", count: 0
          assert_select ".card-title", text: "ブース管理", count: 0
          assert_equal selection, [ @request.session[:current_store_id], @request.session[:current_booth_id] ]
        end
      end
    end
  end

  test "複数店舗・ブースの未選択と有効な閉鎖済み選択を旧一覧で変更しない" do
    actor = User.create!(email: "old-index-selection@example.com", password: "password", role: :system_admin)
    booths = 2.times.map do |i|
      Booth.create!(store: Store.create!(name: "店舗#{i}"), name: "閉鎖#{i}", archived_at: Time.current)
    end
    sign_in actor
    get admin_booths_path
    assert_redirected_to dashboard_path
    assert_nil @request.session[:current_store_id]
    assert_nil @request.session[:current_booth_id]
    post cast_current_booth_path, params: { booth_id: booths.last.id, source: "header" }, as: :json
    assert_response :success
    get admin_booths_path(archived: 1)
    assert_redirected_to dashboard_path
    assert_equal booths.last.id, @request.session[:current_booth_id]
    assert_equal booths.last.store_id, @request.session[:current_store_id]
    post admin_current_store_path, params: { store_id: booths.last.store_id, return_to: admin_booths_path(archived: 1) }, as: :json
    assert_equal dashboard_path, response.parsed_body["redirect_url"]
    post cast_current_booth_path, params: { booth_id: booths.first.id, source: "header", return_to: admin_booths_path }, as: :json
    assert_equal dashboard_path, response.parsed_body["redirect_url"]
  end

  test "旧一覧は認証と管理者の役割を要求する" do
    get admin_booths_path
    assert_redirected_to new_user_session_path
    %i[customer cast].each do |role|
      actor = User.create!(email: "old-index-denied-#{role}@example.com", password: "password", role: role)
      sign_in actor
      get admin_booths_path
      assert_response :forbidden
      sign_out actor
    end
  end
end
