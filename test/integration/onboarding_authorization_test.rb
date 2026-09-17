# frozen_string_literal: true

require "test_helper"

class OnboardingAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "案内対象店舗", onboarding_step: :go_dashboard_for_drinks)
    @admin = User.create!(email: "onboarding-admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    @cast = User.create!(email: "onboarding-cast@example.com", password: "password", role: :cast)
    StoreMembership.create!(store: @store, user: @cast, membership_role: :cast)
    booth = Booth.create!(store: @store, name: "案内確認ブース")
    BoothCast.create!(booth: booth, cast_user: @cast)
  end

  test "cast after store administrator logout neither sees nor advances the store tutorial" do
    sign_in @admin
    get root_path
    assert_select "[data-controller~='onboarding']", count: 1
    delete destroy_user_session_path
    sign_in @cast

    get root_path
    assert_response :ok
    assert_select "[data-controller~='onboarding']", count: 0
    get dashboard_path
    assert_response :ok
    assert_select "[data-controller~='onboarding']", count: 0
    assert_equal "go_dashboard_for_drinks", @store.reload.onboarding_step

    post skip_admin_onboarding_path, params: { store_id: @store.id }, as: :json
    assert_response :forbidden
    assert_equal "go_dashboard_for_drinks", @store.reload.onboarding_step
  end

  test "administrator of the store continues the tutorial on the dashboard" do
    sign_in @admin
    get dashboard_path
    assert_response :ok
    assert_equal "setup_drinks", @store.reload.onboarding_step
    assert_select "[data-controller~='onboarding'][data-onboarding-step-value='setup_drinks']", count: 1
  end

  test "system administrator can continue the selected store tutorial" do
    user = User.create!(email: "onboarding-system@example.com", password: "password", role: :system_admin)
    sign_in user
    post admin_current_store_path, params: { store_id: @store.id }
    get dashboard_path
    assert_response :ok
    assert_equal "setup_drinks", @store.reload.onboarding_step
    assert_select "[data-controller~='onboarding']", count: 1
  end

  test "unset completed and skipped tutorials are not rendered even for the store administrator" do
    sign_in @admin
    [ nil, :completed, :skipped ].each do |step|
      @store.update!(onboarding_step: step)
      get dashboard_path
      assert_response :ok
      assert_select "[data-controller~='onboarding']", count: 0
      if step
        assert_equal step.to_s, @store.reload.onboarding_step
      else
        assert_nil @store.reload.onboarding_step
      end
    end
  end
end
