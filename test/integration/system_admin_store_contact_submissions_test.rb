# frozen_string_literal: true

require "test_helper"

class SystemAdminStoreContactSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "store_contact_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "store_contact_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "store_contact_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "store_contact_system_admin@example.com", password: "password", role: :system_admin)

    @submission = create_store_contact_submission(
      name: "山田 太郎",
      store_name: "Butterflyve Bar 新宿店",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      contactable_time: "平日 10:00-18:00",
      body: "料金や導入までの流れについて相談したいです。"
    )
  end

  test "guest is redirected to login" do
    get system_admin_store_contact_submissions_path
    assert_redirected_to new_user_session_path

    get system_admin_store_contact_submission_path(@submission)
    assert_redirected_to new_user_session_path
  end

  test "non system admins cannot access management screens" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get system_admin_store_contact_submissions_path
      assert_response :forbidden

      get system_admin_store_contact_submission_path(@submission)
      assert_response :forbidden

      sign_out :user
    end
  end

  test "system admin dashboard links to store contact submission management" do
    sign_in @system_admin, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_store_contact_submissions_path, text: /店舗LPお問い合わせ管理/

    sign_out :user

    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get dashboard_path

      assert_response :success
      assert_select "a[href=?]", system_admin_store_contact_submissions_path, count: 0
      assert_no_match "店舗LPお問い合わせ管理", response.body

      sign_out :user
    end
  end

  test "system admin can list store contact submissions ordered by created_at descending" do
    older = @submission
    newer = create_store_contact_submission(
      name: "佐藤 花子",
      store_name: "Newest Store",
      email: "newest@example.com",
      phone_number: "03-1234-5678",
      contactable_time: "",
      body: "最新のお問い合わせです。"
    )
    older.update!(created_at: 2.days.ago, updated_at: 2.days.ago)
    newer.update!(created_at: 1.hour.ago, updated_at: 1.hour.ago)

    sign_in @system_admin, scope: :user

    get system_admin_store_contact_submissions_path

    assert_response :success
    assert_select "h1", "店舗LPお問い合わせ管理"
    assert_select "a[href=?]", system_admin_store_contact_submission_path(older), text: "詳細"
    assert_select "a[href=?]", system_admin_store_contact_submission_path(newer), text: "詳細"
    assert_includes response.body, older.store_name
    assert_includes response.body, newer.store_name
    assert_includes response.body, older.name
    assert_includes response.body, older.email
    assert_includes response.body, older.phone_number
    assert_includes response.body, older.contactable_time
    assert_includes response.body, StoreContactSubmission::SOURCE_STORES_LP
    assert_includes response.body, "料金や導入までの流れ"
    assert_operator response.body.index(newer.store_name), :<, response.body.index(older.store_name)
  end

  test "system admin can view store contact submission details" do
    sign_in @system_admin, scope: :user

    get system_admin_store_contact_submission_path(@submission)

    assert_response :success
    assert_select "h1", "店舗LPお問い合わせ詳細"
    assert_select "a[href=?]", system_admin_store_contact_submissions_path, text: "店舗LPお問い合わせ管理へ"
    assert_includes response.body, @submission.name
    assert_includes response.body, @submission.store_name
    assert_includes response.body, @submission.email
    assert_includes response.body, @submission.phone_number
    assert_includes response.body, @submission.contactable_time
    assert_includes response.body, @submission.body
    assert_includes response.body, @submission.source
  end

  test "existing system admin support inquiry management remains separate" do
    sign_in @system_admin, scope: :user

    get system_admin_support_inquiries_path

    assert_response :success
    assert_select "h1", "お問い合わせ管理"
    assert_select "a[href=?]", system_admin_store_contact_submission_path(@submission), count: 0
    assert_not_includes response.body, @submission.store_name
  end

  private

  def create_store_contact_submission(attributes = {})
    StoreContactSubmission.create!(
      {
        name: "Owner Name",
        store_name: "Sample Store",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00",
        source: StoreContactSubmission::SOURCE_STORES_LP
      }.merge(attributes)
    )
  end
end
