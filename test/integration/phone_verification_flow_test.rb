# frozen_string_literal: true

require "test_helper"

class PhoneVerificationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @deliveries = []
    @fake_sms_client = FakeSmsClient.new(@deliveries)
    Sms::Client.factory = ->(region:) { @fake_sms_client }

    @previous_sms_delivery_mode = ENV["SMS_DELIVERY_MODE"]
    ENV["SMS_DELIVERY_MODE"] = "live"
  end

  teardown do
    Sms::Client.reset_factory!

    if @previous_sms_delivery_mode.nil?
      ENV.delete("SMS_DELIVERY_MODE")
    else
      ENV["SMS_DELIVERY_MODE"] = @previous_sms_delivery_mode
    end
  end

  test "dashboard shows phone verification link" do
    user = User.create!(
      email: "dashboard_phone_link@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    get dashboard_path

    assert_response :success
    assert_includes @response.body, "電話番号認証"
  end

  test "send phone otp redirects to confirm without saving phone_number to user" do
    user = User.create!(
      email: "phone_send@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    post phone_verification_path, params: { phone_number: "09012345678" }

    assert_redirected_to confirm_phone_verification_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "認証コード入力"

    user.reload
    assert_nil user.phone_number
    assert_nil user.phone_verified_at

    verification = PhoneVerification.order(:id).last
    assert_equal user.id, verification.user_id
    assert_equal "+819012345678", verification.phone_number
  end

  test "verify phone otp saves verified phone number to user" do
    user = User.create!(
      email: "phone_verify@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    post phone_verification_path, params: { phone_number: "09012345678" }
    assert_redirected_to confirm_phone_verification_path

    post verify_phone_verification_path, params: { otp_code: latest_otp_code }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "電話番号を認証して登録しました"

    user.reload
    assert_equal "+819012345678", user.phone_number
    assert user.phone_verified_at.present?
  end

  test "verify phone otp rejects phone number already used by another user" do
    User.create!(
      email: "existing_phone_user@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      phone_number: "+819012345678",
      phone_verified_at: Time.current
    )

    user = User.create!(
      email: "new_phone_user@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    post phone_verification_path, params: { phone_number: "09012345678" }
    assert_redirected_to confirm_phone_verification_path

    post verify_phone_verification_path, params: { otp_code: latest_otp_code }

    assert_redirected_to phone_verification_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "この電話番号はすでに他のユーザーに登録されています"

    user.reload
    assert_nil user.phone_number
    assert_nil user.phone_verified_at
  end

  private

  FakeSmsClient = Struct.new(:deliveries) do
    def publish!(phone_number:, message:)
      deliveries << { phone_number:, message: }
    end
  end

  def latest_otp_code
    delivery = @deliveries.last
    assert_not_nil delivery, "SMS delivery が記録されていません"

    message = delivery.fetch(:message)
    code = message[/\d{6}/]

    assert_not_nil code, "SMS本文からOTPコードを抽出できませんでした: #{message.inspect}"
    code
  end
end
