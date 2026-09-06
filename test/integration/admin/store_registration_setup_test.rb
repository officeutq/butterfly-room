# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class Admin::StoreRegistrationSetupTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  setup do
    @tempfiles = []
    @referral_code = ReferralCode.create!(
      code: "INITIAL-STORE-SETUP-#{SecureRandom.hex(3)}",
      enabled: true,
      expires_at: 1.day.from_now
    )
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    @tempfiles.each(&:close!)
  end

  test "registration signs in and redirects an unpublished store to its setup" do
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "initial_setup"
    }

    assert_no_difference -> { completion_events.count } do
      post_registration(from: "stores_lp_202607")
    end

    store = Store.order(:id).last
    assert_redirected_to edit_admin_store_registration_setup_path(store)
    assert_not store.published?
    assert store.onboarding_step_invite_cast?
    assert_equal store.id, @request.session[:current_store_id]
    assert_nil @request.session[:current_booth_id]
    assert_equal(
      {
        "store_id" => store.id,
        "from" => "stores_lp_202607",
        "utm" => {
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "initial_setup"
        }
      },
      @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    )
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_COMPLETION_SESSION_KEY]
  end

  test "setup reuses the store form image editor and AI autofill without publication controls" do
    store = register_store

    get edit_admin_store_registration_setup_path(store)

    assert_response :success
    assert_select "h1", text: "店舗情報を入力しましょう"
    assert_select "form[action=?]", admin_store_registration_setup_path(store)
    assert_select "[data-controller='store-ai-autofill']" \
                  "[data-store-ai-autofill-url-value=?]", admin_store_ai_autofill_path(store)
    assert_select "button[data-action='store-ai-autofill#search']", count: 1
    assert_select "section[data-controller='image-attachment-editor']" \
                  "[data-image-attachment-editor-ratio-key-value='social']", count: 1
    assert_select "select[name='store[published]']", count: 0
    assert_select "input[name='store[published]']", count: 0
    assert_select "input[name='store[sales_support_company]']", count: 0
    assert_select "input[type=submit][value='保存して公開']", count: 1
    assert_select "input[type=submit][value='店舗情報を保存して公開する']", count: 1
  end

  test "unchanged setup publishes and records one completion" do
    get stores_lp_202607_path, params: { utm_source: "meta" }
    store = register_store(from: "stores_lp_202607")

    assert_difference -> { completion_events.count }, 1 do
      patch admin_store_registration_setup_path(store), params: {
        store: { name: store.name }
      }
    end

    assert_redirected_to stores_registration_thanks_path
    assert store.reload.published?
    assert_equal store, completion_events.last.completion_record
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    assert_equal(
      {
        "store_id" => store.id,
        "from" => "stores_lp_202607",
        "utm" => { "utm_source" => "meta" }
      },
      @request.session[ApplicationController::STORE_REGISTRATION_COMPLETION_SESSION_KEY]
    )
  end

  test "setup saves common information and ignores publication parameters" do
    store = register_store

    patch admin_store_registration_setup_path(store), params: {
      store: {
        name: "初回設定後店舗",
        area: "渋谷",
        description: "店舗概要",
        published: "0",
        sales_support_company: "1"
      }
    }

    assert_redirected_to stores_registration_thanks_path
    store.reload
    assert_equal "初回設定後店舗", store.name
    assert_equal "渋谷", store.area
    assert_equal "店舗概要", store.description
    assert store.published?
    assert_not store.sales_support_company?
  end

  test "setup can publish with a new image pair and returns JSON" do
    store = register_store

    patch admin_store_registration_setup_path(store),
          params: {
            store: { name: "画像設定店舗" },
            image_pair: replace_pair_params(store)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "complete", body.fetch("state")
    assert_equal stores_registration_thanks_path, body.fetch("redirect_url")
    store.reload
    assert store.published?
    assert store.thumbnail_source.attached?
    assert store.thumbnail.attached?
    assert_equal store.thumbnail_source.blob.id, store.thumbnail_crop_data.fetch("sourceBlobId")
  end

  test "validation failure keeps the store unpublished and pending" do
    store = register_store
    pending = @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]

    assert_no_difference -> { completion_events.count } do
      patch admin_store_registration_setup_path(store), params: {
        store: { name: "", description: "保存されない" }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".alert-danger", text: /店舗名/
    store.reload
    assert_not store.published?
    assert_not_equal "保存されない", store.description
    assert_equal pending, @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_COMPLETION_SESSION_KEY]
  end

  test "invalid image keeps information images publication and pending unchanged" do
    store = register_store
    pending = @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    blob_count = ActiveStorage::Blob.count

    assert_no_difference -> { completion_events.count } do
      patch admin_store_registration_setup_path(store),
            params: {
              store: { name: "保存されない店舗名" },
              image_pair: replace_pair_params(store, display_width: 1024, display_height: 1024)
            },
            headers: { "ACCEPT" => "application/json" }
    end

    assert_response :unprocessable_entity
    store.reload
    assert_not store.published?
    assert_not_equal "保存されない店舗名", store.name
    assert_not store.thumbnail_source.attached?
    assert_not store.thumbnail.attached?
    assert_equal blob_count, ActiveStorage::Blob.count
    assert_equal pending, @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
  end

  test "missing pending redirects to the selected store edit without saving" do
    store, user = create_store_admin
    sign_in user, scope: :user
    post admin_current_store_path, params: { store_id: store.id }

    get edit_admin_store_registration_setup_path(store)

    assert_redirected_to edit_admin_store_path(store)
    assert_not store.reload.published?
  end

  test "route store mismatch redirects to the pending current store" do
    pending_store = register_store
    other_store = Store.create!(name: "別店舗", published: false)
    StoreMembership.create!(
      store: other_store,
      user: User.find_by!(email: @registered_email),
      membership_role: :admin
    )

    patch admin_store_registration_setup_path(other_store), params: {
      store: { name: "改ざん更新" }
    }

    assert_redirected_to edit_admin_store_path(pending_store)
    assert_equal "別店舗", other_store.reload.name
    assert_not other_store.published?
    assert_not pending_store.reload.published?
  end

  test "revoked store administrator cannot open or complete setup" do
    store = register_store
    StoreMembership.where(store:).delete_all

    patch admin_store_registration_setup_path(store), params: {
      store: { name: "権限外更新" }
    }

    assert_redirected_to dashboard_path
    assert_not store.reload.published?
    assert_equal 0, completion_events.count
  end

  test "a second submission after completion does not record another event" do
    get stores_lp_202607_path
    store = register_store(from: "stores_lp_202607")
    patch admin_store_registration_setup_path(store), params: { store: { name: store.name } }
    assert_equal 1, completion_events.count

    assert_no_difference -> { completion_events.count } do
      patch admin_store_registration_setup_path(store), params: {
        store: { name: "二重送信" }
      }
    end

    assert_redirected_to edit_admin_store_path(store)
    assert_not_equal "二重送信", store.reload.name
  end

  test "publishing from the normal store edit does not complete registration" do
    get stores_lp_202607_path
    store = register_store(from: "stores_lp_202607")
    pending = @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]

    assert_no_difference -> { completion_events.count } do
      patch admin_store_path(store), params: {
        store: { name: store.name, published: "1" }
      }
    end

    assert_redirected_to dashboard_path
    assert store.reload.published?
    assert_equal pending, @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_COMPLETION_SESSION_KEY]
  end

  test "setup requires authentication" do
    store = Store.create!(name: "認証必須店舗", published: false)

    get edit_admin_store_registration_setup_path(store)

    assert_redirected_to new_user_session_path
  end

  private

  def register_store(from: nil)
    post_registration(from:)
    Store.order(:id).last
  end

  def post_registration(from: nil)
    @registered_email = "initial-store-setup-#{SecureRandom.hex(4)}@example.com"
    path = from.present? ? stores_registrations_path(from:) : stores_registrations_path
    post path, params: {
      store_registration: {
        store_name: "初回設定対象店舗",
        email: @registered_email,
        password: "password",
        password_confirmation: "password",
        referral_code: @referral_code.code
      }
    }
  end

  def create_store_admin
    store = Store.create!(name: "選択店舗", published: false)
    user = User.create!(
      email: "initial-setup-existing-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store:, user:, membership_role: :admin)
    [ store, user ]
  end

  def completion_events
    LpAnalytics::Event.where(event_type: "store_registration_complete")
  end

  def replace_pair_params(store, display_width: 1200, display_height: 630)
    {
      operation: "replace",
      source: jpeg_upload(1200, 630),
      display: jpeg_upload(display_width, display_height),
      crop_data: JSON.generate(crop_data),
      expected: ImageAttachments::StagedPairUpdateService.capture(
        record: store,
        purpose: :thumbnail
      ).to_h
    }
  end

  def crop_data
    {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "source" => { "width" => 1200, "height" => 630 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 630 },
      "zoom" => 1.0,
      "output" => {
        "width" => 1200,
        "height" => 630,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    }
  end

  def jpeg_upload(width, height)
    tempfile = Tempfile.new([ "registration-setup", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:purple"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    Rack::Test::UploadedFile.new(
      tempfile.path,
      "image/jpeg",
      true,
      original_filename: "store.jpg"
    )
  end
end
