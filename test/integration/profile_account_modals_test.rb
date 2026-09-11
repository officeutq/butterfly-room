# frozen_string_literal: true

require "test_helper"

class ProfileAccountModalsTest < ActionDispatch::IntegrationTest
  FRAME_HEADERS = { "Turbo-Frame" => "modal" }.freeze
  SUBMIT_HEADERS = FRAME_HEADERS.merge("Accept" => "text/vnd.turbo-stream.html, text/html").freeze

  setup do
    @user = User.create!(email: "account-modal@example.com", password: "password", role: :customer)
    sign_in @user, scope: :user
    @deliveries = []
    deliveries = @deliveries
    Sms::Client.factory = ->(region:) { FakeSmsClient.new(deliveries) }
    @previous_mode = ENV["SMS_DELIVERY_MODE"]
    ENV["SMS_DELIVERY_MODE"] = "live"
  end

  teardown do
    Sms::Client.reset_factory!
    @previous_mode.nil? ? ENV.delete("SMS_DELIVERY_MODE") : ENV["SMS_DELIVERY_MODE"] = @previous_mode
  end

  test "all roles have private account actions and the dashboard profile badge" do
    User.roles.each_key do |role|
      @user.update!(role:)
      get edit_profile_path
      assert_response :success
      assert_select ".profile-edit__account", text: /メールアドレス・電話番号は公開プロフィールに表示されません。/
      assert_select "a[href='#{edit_email_change_path}'][data-turbo-frame='modal']"
      assert_select "a[href='#{phone_verification_path}'][data-turbo-frame='modal']"
      assert_select "form#profile-edit-form form", count: 0

      [ false, true ].each do |verified|
        @user.update!(phone_number: verified ? "+819012345678" : nil, phone_verified_at: verified ? Time.current : nil)
        get dashboard_path
        assert_select "a[href='#{edit_profile_path}'] .badge", text: verified ? "電話番号認証済み" : "電話番号未認証"
        assert_select "a[href='#{phone_verification_path}']", count: 0
      end

      get edit_email_change_path, headers: FRAME_HEADERS
      assert_modal "メールアドレス変更"
      get phone_verification_path, headers: FRAME_HEADERS
      assert_modal "電話番号認証"
    end
  end

  test "email success updates only email and retains authentication" do
    patch email_change_path, params: { user: { email: "updated-modal@example.com", current_password: "password" } }, headers: SUBMIT_HEADERS
    assert_account_completion "profile-account-email"
    assert_equal "updated-modal@example.com", @user.reload.email
    get edit_profile_path
    assert_response :success
    assert_select "#profile-account-email", text: /updated-modal@example.com/
    save_unchanged_profile
    assert_equal "updated-modal@example.com", @user.reload.email
  end

  test "email failures remain in the modal without persisting or echoing the password" do
    User.create!(email: "taken-modal@example.com", password: "password", role: :customer)
    [ [ "new@example.com", "wrong-password" ], [ "invalid", "password" ], [ "taken-modal@example.com", "password" ] ].each do |email, password|
      patch email_change_path, params: { user: { email:, current_password: password } }, headers: SUBMIT_HEADERS
      assert_response :unprocessable_entity
      assert_modal "メールアドレス変更"
      assert_select "[role='alert'] li", minimum: 1
      assert_select "input[name='user[current_password]'][value]", count: 0
      assert_equal "account-modal@example.com", @user.reload.email
    end
  end

  test "phone send remains open and supports reopen and editing without changing registered number" do
    @user.update!(phone_number: "+819011112222", phone_verified_at: Time.current)
    send_code
    assert_response :success
    assert_modal "認証コード入力"
    assert_select "form form", count: 0
    assert_select "[data-controller='account-modal-complete']", count: 0
    assert_equal "+819011112222", @user.reload.phone_number
    get phone_verification_path, headers: FRAME_HEADERS
    assert_modal "認証コード入力"
    get phone_verification_path(edit: "1"), headers: FRAME_HEADERS
    assert_modal "電話番号認証"
    assert_select "input[name='phone_number'][value='090-1234-5678']"
    assert_equal 1, @deliveries.size
  end

  test "phone completion updates only phone and clears pending state" do
    send_code
    post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
    assert_account_completion "profile-account-phone"
    assert_equal "+819012345678", @user.reload.phone_number
    assert @user.phone_verified?
    assert PhoneVerification.order(:id).last.consumed_at.present?
    save_unchanged_profile
    assert_equal "+819012345678", @user.reload.phone_number
    assert @user.phone_verified?
    get phone_verification_path, headers: FRAME_HEADERS
    assert_modal "電話番号認証"
  end

  test "phone errors stay inside the modal and failed attempts persist" do
    send_code
    correct_code = code
    incorrect_code = correct_code == "000000" ? "111111" : "000000"
    4.times do |index|
      post verify_phone_verification_path, params: { otp_code: incorrect_code }, headers: SUBMIT_HEADERS
      assert_response :unprocessable_entity
      assert_modal "認証コード入力"
      assert_select "[role='alert']", text: "認証コードが正しくありません"
      assert_equal index + 1, PhoneVerification.order(:id).last.attempts_count
    end
    post verify_phone_verification_path, params: { otp_code: incorrect_code }, headers: SUBMIT_HEADERS
    assert_select "[role='alert']", text: /上限/
    post verify_phone_verification_path, params: { otp_code: correct_code }, headers: SUBMIT_HEADERS
    assert_select "[role='alert']", text: /上限/
    refute @user.reload.phone_verified?
  end

  test "resend restriction and expiration are shown in the modal" do
    send_code
    send_code
    assert_response :unprocessable_entity
    assert_modal "認証コード入力"
    assert_select "[role='alert']", text: /60秒/
    assert_equal 1, @deliveries.size
    travel 61.seconds do
      send_code
      assert_response :success
      assert_equal 2, @deliveries.size
    end
    travel 7.minutes do
      post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: /有効期限/
    end
    refute @user.reload.phone_verified?
  end

  test "duplicate number does not consume the code or change the existing number" do
    @user.update!(phone_number: "+819011112222", phone_verified_at: Time.current)
    User.create!(email: "number-owner@example.com", password: "password", role: :customer, phone_number: "+819012345678")
    send_code
    post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    assert_modal "電話番号認証"
    assert_select "[role='alert']", text: /他のユーザー/
    assert_nil PhoneVerification.order(:id).last.consumed_at
    assert_equal "+819011112222", @user.reload.phone_number
  end

  test "invalid phone and missing pending state show the input modal" do
    post phone_verification_path, params: { phone_number: "invalid" }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    assert_modal "電話番号認証"
    assert_select "[role='alert']", text: /形式/
    post verify_phone_verification_path, params: { otp_code: "123456" }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /先に電話番号/
    assert_empty @deliveries
  end

  test "failed account validation rolls back code consumption" do
    send_code
    @user.update_column(:bio, "a" * 501)
    post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    assert_nil PhoneVerification.order(:id).last.consumed_at
    assert_nil PhoneVerification.order(:id).last.verified_at
    refute @user.reload.phone_verified?
    assert_select "p", text: /電話番号はまだ認証されていません/
  end

  test "SMS delivery failure stays inside the modal" do
    Sms::Client.factory = ->(region:) { FailingSmsClient.new }
    send_code
    assert_response :unprocessable_entity
    assert_modal "電話番号認証"
    assert_select "[role='alert']", text: /送信できませんでした/
    refute @user.reload.phone_verified?
  end

  test "another user's code cannot register a number" do
    other = User.create!(email: "other-code@example.com", password: "password", role: :customer)
    PhoneVerifications::IssueOtpService.new(phone_number: "09012345678", purpose: PhoneVerification::PURPOSE_VERIFY_PHONE, user: other).call!
    send_code # 再送制限が発生しても他人のコードで認証できない。
    post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    refute @user.reload.phone_verified?
  end

  test "used code is rejected in the modal" do
    send_code
    PhoneVerification.order(:id).last.update!(consumed_at: Time.current)
    post verify_phone_verification_path, params: { otp_code: code }, headers: SUBMIT_HEADERS
    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /すでに使用/
    refute @user.reload.phone_verified?
  end

  test "account changes cannot be submitted through normal profile save" do
    patch profile_path, params: { user: { display_name: "通常の保存", email: "injected@example.com", phone_number: "+819099999999", phone_verified_at: Time.current } }
    assert_redirected_to user_path(@user)
    assert_equal "通常の保存", @user.reload.display_name
    assert_equal "account-modal@example.com", @user.email
    assert_nil @user.phone_number
    assert_nil @user.phone_verified_at
  end

  test "guest cannot open or submit account modals" do
    sign_out @user
    get edit_email_change_path, headers: FRAME_HEADERS
    assert_redirected_to new_user_session_path
    get phone_verification_path, headers: FRAME_HEADERS
    assert_redirected_to new_user_session_path
    patch email_change_path, params: { user: { email: "guest@example.com", current_password: "password" } }, headers: FRAME_HEADERS
    assert_redirected_to new_user_session_path
    post phone_verification_path, params: { phone_number: "09012345678" }, headers: FRAME_HEADERS
    assert_redirected_to new_user_session_path
    post verify_phone_verification_path, params: { otp_code: "123456" }, headers: FRAME_HEADERS
    assert_redirected_to new_user_session_path
  end

  private

  FakeSmsClient = Struct.new(:deliveries) do
    def publish!(phone_number:, message:)
      deliveries << message
    end
  end

  class FailingSmsClient
    def publish!(**)
      raise Sms::Sender::Error
    end
  end

  def send_code
    post phone_verification_path, params: { phone_number: "09012345678" }, headers: SUBMIT_HEADERS
  end

  def code
    @deliveries.last[/\d{6}/]
  end

  def assert_modal(title)
    assert_select "turbo-frame#modal .modal h1", text: title
    assert_select "form#profile-edit-form", count: 0
  end

  def save_unchanged_profile
    patch profile_path, params: { user: { display_name: @user.display_name, bio: @user.bio } }
    assert_redirected_to user_path(@user)
  end

  def assert_account_completion(target)
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='#{target}']", count: 1
    message = target == "profile-account-email" ? "✓ メールアドレスの変更を保存しました" : "✓ 電話番号を認証して保存しました"
    assert_select "turbo-stream[action='update'][target='#{target}-notice'] template", text: message, count: 1
    assert_select "turbo-stream[action='append'][target='modal']", count: 1
    assert_select "turbo-stream", count: 3
    assert_select "form#profile-edit-form", count: 0
  end
end
