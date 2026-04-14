# frozen_string_literal: true

require "test_helper"

class PhoneLoginFlowTest < ActionDispatch::IntegrationTest
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

  test "login page shows phone login link" do
    get new_user_session_path

    assert_response :success
    assert_includes @response.body, "電話番号でログイン"
  end

  test "verified phone number can log in with otp" do
    user = User.create!(
      email: "phone_login_success@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      phone_number: "+819012345678",
      phone_verified_at: Time.current
    )

    post phone_session_path, params: { phone_number: "09012345678" }

    assert_redirected_to confirm_phone_session_path

    post verify_phone_session_path, params: { otp_code: latest_otp_code }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ログインしました"

    delete destroy_user_session_path
    assert_redirected_to root_path

    post phone_session_path, params: { phone_number: "09012345678" }
    assert_redirected_to confirm_phone_session_path

    post verify_phone_session_path, params: { otp_code: latest_otp_code }
    assert_redirected_to root_path

    assert_equal user.id, User.find_by(email: "phone_login_success@example.com").id
  end

  test "unverified phone number does not send otp and cannot log in" do
    User.create!(
      email: "phone_login_unverified@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      phone_number: "+819012345678",
      phone_verified_at: nil
    )

    post phone_session_path, params: { phone_number: "09012345678" }

    assert_redirected_to confirm_phone_session_path
    assert_empty @deliveries

    post verify_phone_session_path, params: { otp_code: "123456" }

    assert_redirected_to confirm_phone_session_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "電話番号または認証コードが正しくありません"
  end

  test "unknown phone number does not expose account existence" do
    post phone_session_path, params: { phone_number: "09099999999" }

    assert_redirected_to confirm_phone_session_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "認証コード入力"

    assert_empty @deliveries
  end

  test "wrong otp cannot log in" do
    User.create!(
      email: "phone_login_wrong_otp@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      phone_number: "+819012345678",
      phone_verified_at: Time.current
    )

    post phone_session_path, params: { phone_number: "09012345678" }

    assert_redirected_to confirm_phone_session_path

    post verify_phone_session_path, params: { otp_code: "999999" }

    assert_redirected_to confirm_phone_session_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "電話番号または認証コードが正しくありません"
  end

  test "existing email login still works" do
    user = User.create!(
      email: "existing_email_login@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password"
      }
    }

    assert_redirected_to root_path
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
