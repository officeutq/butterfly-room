# frozen_string_literal: true

require "test_helper"

class StoreLpAttributionTest < ActionDispatch::IntegrationTest
  test "store LP 202607 stores sanitized UTM attribution in session" do
    get stores_lp_202607_path, params: {
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607",
      utm_content: "flyer_a",
      ignored: "value"
    }

    assert_response :success
    assert_select "a[href=?]", stores_contact_path(from: "stores_lp_202607"), minimum: 1
    assert_select "a[href=?]", stores_new_registration_path(from: "stores_lp_202607"), minimum: 1
    assert_no_match(/utm_source/, response.body)
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm_source" => "meta",
        "utm_medium" => "paid_social",
        "utm_campaign" => "store_recruit_202607",
        "utm_content" => "flyer_a"
      },
      @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    )
  end

  test "store LP 202607 ignores blank array hash and overlong UTM values safely" do
    get stores_lp_202607_path, params: {
      utm_source: [ "meta" ],
      utm_medium: { value: "paid_social" },
      utm_campaign: " ",
      utm_content: "a" * 120
    }

    assert_response :success
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm_content" => "a" * ApplicationController::UTM_PARAM_MAX_LENGTH
      },
      @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    )
  end

  test "store LP 202607 overwrites attribution and clears it when UTM is missing" do
    get stores_lp_202607_path, params: { ref: "1001", utm_source: "meta", utm_medium: "paid_social" }
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]

    get stores_lp_202607_path, params: { ref: "2002", utm_source: "agency_x", utm_campaign: "store_recruit_202607" }
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm_source" => "agency_x",
        "utm_campaign" => "store_recruit_202607"
      },
      @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    )
    assert_equal "2002", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]

    get stores_lp_202607_path
    assert_nil @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "store LP 202607 keeps ref in registration link without exposing UTM params" do
    get stores_lp_202607_path, params: {
      ref: "1001",
      utm_source: "meta",
      utm_medium: "paid_social"
    }

    assert_response :success
    assert_select "a[href=?]", stores_new_registration_path(ref: "1001", from: "stores_lp_202607"), minimum: 1
    assert_no_match(/utm_source/, response.body)
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "store LP 202607 sanitizes ref before storing it in session" do
    get stores_lp_202607_path, params: { ref: "  #{"1" * 120}  " }

    assert_response :success
    assert_equal(
      "1" * ApplicationController::STORE_LP_202607_REF_MAX_LENGTH,
      @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    )

    get stores_lp_202607_path, params: { ref: [ "1001" ], utm_source: "meta" }

    assert_response :success
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "store LP 202607 internal return preserves attribution and ref once" do
    get stores_lp_202607_path, params: {
      ref: "1001",
      utm_source: "meta",
      utm_medium: "paid_social"
    }

    get stores_lp_202607_return_path

    assert_redirected_to stores_lp_202607_path(ref: "1001")
    assert_equal true, @request.session[ApplicationController::PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]

    follow_redirect!

    assert_response :success
    assert_nil @request.session[ApplicationController::PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    assert_select "a[href=?]", stores_new_registration_path(ref: "1001", from: "stores_lp_202607"), minimum: 1
    assert_no_match(/utm_source/, response.body)

    get stores_lp_202607_path

    assert_response :success
    assert_nil @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "store LP 202607 internal return without ref redirects without query" do
    get stores_lp_202607_path, params: { utm_source: "meta" }

    get stores_lp_202607_return_path

    assert_redirected_to stores_lp_202607_path
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "current store LP does not create 202607 attribution session" do
    get stores_lp_path, params: { utm_source: "meta", utm_medium: "paid_social" }

    assert_response :success
    assert_nil @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end
end
