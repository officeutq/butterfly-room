# frozen_string_literal: true

require "test_helper"

class Stores::AdvanceOnboardingTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "権限確認店舗", onboarding_step: :go_dashboard_for_drinks)
  end

  test "non administrators cannot advance or skip even with a membership" do
    [ :customer, :cast, :store_admin ].each do |role|
      user = User.create!(email: "onboarding-#{role}@example.com", password: "password", role: role)
      StoreMembership.create!(store: @store, user: user, membership_role: :cast)
      assert_no_progress(user)
    end
  end

  test "another stores administrator and a deleted administrator cannot change progress" do
    other = Store.create!(name: "別店舗")
    admin = User.create!(email: "onboarding-other@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: other, user: admin, membership_role: :admin)
    assert_no_progress(admin)
    StoreMembership.create!(store: @store, user: admin, membership_role: :admin)
    admin.update!(deleted_at: Time.current)
    assert_no_progress(admin)
  end

  test "guests cannot change progress" do
    assert_no_progress(nil)
  end

  private

  def assert_no_progress(actor)
    [ :dashboard, :skip ].each do |action|
      Stores::AdvanceOnboarding.call!(store: @store, actor: actor, action: action)
      assert_equal "go_dashboard_for_drinks", @store.reload.onboarding_step
    end
  end
end
