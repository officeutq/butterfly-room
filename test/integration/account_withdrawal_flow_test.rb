# frozen_string_literal: true

require "test_helper"

class AccountWithdrawalFlowTest < ActionDispatch::IntegrationTest
  test "profile and header show the modal entry points without the build label" do
    user = create_user("withdrawal-entry", :customer)
    sign_in user, scope: :user

    get edit_profile_path

    assert_response :success
    document = Nokogiri::HTML(response.body)
    links = document.css("a[href='#{account_withdrawal_path}']")
    assert_equal 2, links.size
    profile_link = links.find { |link| link["class"].to_s.include?("btn-link") }
    assert_equal "退会する", profile_link.text.strip
    assert_nil document.at_css(".card.border-danger")
    assert_includes response.body, "退会する"
    assert_not_includes response.body, "Butterflyve Build"
  end

  test "the modal shows role-specific warnings" do
    cast = create_user("withdrawal-modal-cast", :cast)
    sign_in cast, scope: :user

    get account_withdrawal_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "退会しますか？"
    assert_includes response.body, "所属するすべての店舗からキャスト登録を解除"
    assert_includes response.body, "現在のパスワード"
  end

  test "the modal shows customer and store administrator warnings" do
    customer = create_user("withdrawal-modal-customer", :customer)
    sign_in customer, scope: :user

    get account_withdrawal_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "保有ポイント、予約ポイント、処理中の購入"

    sign_out customer
    store_admin = create_user("withdrawal-modal-store-admin", :store_admin)
    sign_in store_admin, scope: :user

    get account_withdrawal_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "他に有効な管理者がいない店舗は非公開"
    assert_includes response.body, "他に有効な管理者がいる店舗は現状態を維持"
  end

  test "wrong password and missing confirmation do not retire the user" do
    user = create_user("withdrawal-invalid", :customer)
    sign_in user, scope: :user

    delete account_withdrawal_path,
           params: { account_withdrawal: { current_password: "wrong", confirmed: "0" } },
           headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_includes response.body, "現在のパスワードが正しくありません"
    assert_includes response.body, "退会に関する注意事項を確認してください"
    assert_not user.reload.deleted?
  end

  test "a valid request retires and signs out the user" do
    user = create_user("withdrawal-success", :customer)
    sign_in user, scope: :user

    delete account_withdrawal_path, params: {
      account_withdrawal: {
        current_password: "password",
        confirmed: "1"
      }
    }

    assert_response :see_other
    assert_redirected_to new_user_session_path
    assert user.reload.deleted?

    get edit_profile_path
    assert_redirected_to new_user_session_path
  end

  test "cast and store administrator can retire through the endpoint" do
    %i[cast store_admin].each do |role|
      user = create_user("withdrawal-success-#{role}", role)
      sign_in user, scope: :user

      delete account_withdrawal_path, params: {
        account_withdrawal: {
          current_password: "password",
          confirmed: "1"
        }
      }

      assert_response :see_other
      assert_redirected_to new_user_session_path
      assert user.reload.deleted?
    end
  end

  test "a service failure keeps the user active and signed in" do
    user = create_user("withdrawal-service-failure", :cast)
    store = Store.create!(name: "Withdrawal Failure Store")
    membership = StoreMembership.create!(store:, user:, membership_role: :cast)
    booth = Booth.create!(store:, name: "Withdrawal Failure Booth", status: :live)
    BoothCast.create!(booth:, cast_user: user)
    sign_in user, scope: :user

    delete account_withdrawal_path,
           params: {
             account_withdrawal: {
               current_password: "password",
               confirmed: "1"
             }
           },
           headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_includes response.body, "退会処理を完了できませんでした"
    assert_not user.reload.deleted?
    assert StoreMembership.exists?(membership.id)
    assert_not booth.reload.archived?

    get edit_profile_path
    assert_response :success
  end

  test "a turbo frame success returns the login redirect marker" do
    user = create_user("withdrawal-turbo-success", :customer)
    sign_in user, scope: :user

    delete account_withdrawal_path,
           params: {
             account_withdrawal: {
               current_password: "password",
               confirmed: "1"
             }
           },
           headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "data-redirect-url=\"#{new_user_session_path}\""
    assert user.reload.deleted?
  end

  test "system administrators do not see or access the withdrawal flow" do
    system_admin = create_user("withdrawal-ui-system", :system_admin)
    sign_in system_admin, scope: :user

    get edit_profile_path
    assert_response :success
    assert_not_includes response.body, account_withdrawal_path

    get account_withdrawal_path
    assert_response :forbidden

    delete account_withdrawal_path, params: {
      account_withdrawal: { current_password: "password", confirmed: "1" }
    }
    assert_response :forbidden
    assert_not system_admin.reload.deleted?
  end

  test "an unauthenticated request is redirected to login" do
    get account_withdrawal_path
    assert_redirected_to new_user_session_path

    delete account_withdrawal_path
    assert_redirected_to new_user_session_path
  end

  private

  def create_user(prefix, role)
    User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:
    )
  end
end
