# frozen_string_literal: true

require "test_helper"

class SystemAdminStoreContactSubmissionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    @previous_admin_email = ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY]
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "current-admin@example.com"

    @customer = User.create!(email: "store_contact_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "store_contact_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "store_contact_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "store_contact_system_admin@example.com", password: "password", role: :system_admin)

    @submission = create_store_contact_submission(
      name: "山田 太郎",
      store_name: "Butterflyve Bar 新宿店",
      business_type: "ガールズバー",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      contactable_time: "平日 10:00-18:00",
      body: "料金や導入までの流れについて相談したいです。"
    )
  end

  teardown do
    restore_admin_email_env
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "guest is redirected to login" do
    get system_admin_store_contact_submissions_path
    assert_redirected_to new_user_session_path

    get system_admin_store_contact_submission_path(@submission)
    assert_redirected_to new_user_session_path

    assert_no_enqueued_emails do
      post resend_admin_notification_system_admin_store_contact_submission_path(@submission)
    end
    assert_redirected_to new_user_session_path
  end

  test "non system admins cannot access management screens" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get system_admin_store_contact_submissions_path
      assert_response :forbidden

      get system_admin_store_contact_submission_path(@submission)
      assert_response :forbidden

      assert_no_enqueued_emails do
        post resend_admin_notification_system_admin_store_contact_submission_path(@submission)
      end
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
      business_type: "",
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
    assert_includes response.body, "current-admin@example.com"
    assert_select "form[action=?]",
      resend_admin_notification_system_admin_store_contact_submission_path(older) do
      assert_select "button", text: "管理者宛メールを再送"
      assert_select "button[data-turbo-confirm=?]",
        "#{older.store_name}（#{older.name}）のお問い合わせを current-admin@example.com へ再送します。よろしいですか？"
      assert_select "button[data-turbo-submits-with=?]", "再送受付中…"
    end
    assert_includes response.body, older.store_name
    assert_includes response.body, older.business_type
    assert_includes response.body, newer.store_name
    assert_includes response.body, older.name
    assert_includes response.body, older.email
    assert_includes response.body, older.phone_number
    assert_includes response.body, older.contactable_time
    assert_includes response.body, StoreContactSubmission::SOURCE_STORES_LP
    assert_includes response.body, "料金や導入までの流れ"
    assert_operator response.body.index(newer.store_name), :<, response.body.index(older.store_name)
  end

  test "system admin can enqueue one admin notification from the index" do
    sign_in @system_admin, scope: :user

    assert_enqueued_emails 1 do
      assert_enqueued_email_with(
        StoreContactSubmissionMailer,
        :admin_notification,
        params: { store_contact_submission: @submission }
      ) do
        post resend_admin_notification_system_admin_store_contact_submission_path(@submission)
      end
    end

    assert_redirected_to system_admin_store_contact_submissions_path
    follow_redirect!
    assert_select ".alert", text: /管理者宛メールの再送を受け付けました/
  end

  test "admin notification is not enqueued when the admin address is not configured" do
    ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    sign_in @system_admin, scope: :user

    get system_admin_store_contact_submissions_path

    assert_response :success
    assert_select ".alert-warning", text: /未設定のため、管理者宛メールを再送できません/
    assert_select "form[action=?]",
      resend_admin_notification_system_admin_store_contact_submission_path(@submission),
      count: 0
    assert_select "button[disabled]", text: "管理者宛メールを再送", minimum: 1

    assert_no_enqueued_emails do
      post resend_admin_notification_system_admin_store_contact_submission_path(@submission)
    end

    assert_redirected_to system_admin_store_contact_submissions_path
    follow_redirect!
    assert_select ".alert", text: /管理者メールアドレスが設定されていないため、再送できません/
  end

  test "resending a missing submission returns not found" do
    sign_in @system_admin, scope: :user

    assert_no_enqueued_emails do
      post resend_admin_notification_system_admin_store_contact_submission_path(id: 0)
    end

    assert_response :not_found
  end

  test "system admin can view store contact submission details" do
    sign_in @system_admin, scope: :user

    get system_admin_store_contact_submission_path(@submission)

    assert_response :success
    assert_select "h1", "店舗LPお問い合わせ詳細"
    assert_select "a[href=?]", system_admin_store_contact_submissions_path, text: "店舗LPお問い合わせ管理へ"
    assert_includes response.body, @submission.name
    assert_includes response.body, @submission.store_name
    assert_includes response.body, @submission.business_type
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
        business_type: "Girls Bar",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00",
        source: StoreContactSubmission::SOURCE_STORES_LP
      }.merge(attributes)
    )
  end

  def restore_admin_email_env
    if @previous_admin_email.nil?
      ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    else
      ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = @previous_admin_email
    end
  end
end
