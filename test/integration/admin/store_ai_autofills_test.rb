# frozen_string_literal: true

require "test_helper"

class Admin::StoreAiAutofillsTest < ActionDispatch::IntegrationTest
  setup do
    Admin::StoreAiAutofillsController::RATE_LIMIT_STORE.clear
    @store = Store.create!(name: "検索対象店舗", description: "保存済み概要")
    @other_store = Store.create!(name: "権限外店舗")
    @store_admin = User.create!(
      email: "store_ai_autofill_admin@example.com",
      password: "password",
      role: :store_admin
    )
    @system_admin = User.create!(
      email: "store_ai_autofill_system@example.com",
      password: "password",
      role: :system_admin
    )
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "store admin can search its store without changing the database" do
    sign_in @store_admin, scope: :user
    original_attributes = @store.attributes

    with_search_result(partial_result) do
      post admin_store_ai_autofill_path(@store),
           params: { store: { name: "改ざん名", published: true } },
           as: :json
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal "partial", body.fetch("status")
    assert_equal "渋谷区", body.dig("fields", "area")
    assert_equal original_attributes, @store.reload.attributes
  end

  test "store admin cannot search another store" do
    sign_in @store_admin, scope: :user

    service = Object.new
    service.define_singleton_method(:call) { flunk("service must not be called") }

    with_search_service(service) do
      post admin_store_ai_autofill_path(@other_store), as: :json
    end

    assert_response :forbidden
  end

  test "system admin can search any store" do
    sign_in @system_admin, scope: :user

    with_search_result(partial_result) do
      post admin_store_ai_autofill_path(@other_store), as: :json
    end

    assert_response :ok
  end

  test "edit page contains the AI search control and dedicated modal" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store)

    assert_response :ok
    assert_select "[data-controller~='store-ai-autofill']"
    assert_select "button[data-action='store-ai-autofill#search']", text: /AIで店舗情報を自動入力/
    assert_select ".modal[data-store-ai-autofill-target='modal']"
  end

  test "rate limits the fourth search in ten minutes" do
    sign_in @store_admin, scope: :user

    with_search_result(partial_result) do
      3.times do
        post admin_store_ai_autofill_path(@store), as: :json
        assert_response :ok
      end

      post admin_store_ai_autofill_path(@store), as: :json
    end

    assert_response :too_many_requests
    assert_equal(
      { "status" => "error", "error_code" => "rate_limited" },
      response.parsed_body
    )
  end

  {
    Stores::AiAutofill::Settings::ConfigurationError => [ :service_unavailable, "configuration_error" ],
    Stores::AiAutofill::ResponsesClient::RateLimitedError => [ :service_unavailable, "openai_rate_limited" ],
    Stores::AiAutofill::ResponsesClient::TimeoutError => [ :gateway_timeout, "timeout" ],
    Stores::AiAutofill::ResponsesClient::UnavailableError => [ :bad_gateway, "openai_unavailable" ],
    Stores::AiAutofill::ResponsesClient::InvalidResponseError => [ :bad_gateway, "invalid_response" ]
  }.each do |error_class, (expected_status, expected_code)|
    test "maps #{error_class.name} to #{expected_code}" do
      sign_in @store_admin, scope: :user

      service = Object.new
      service.define_singleton_method(:call) { raise error_class, "test" }

      with_search_service(service) do
        post admin_store_ai_autofill_path(@store), as: :json
      end

      assert_response expected_status
      assert_equal({ "status" => "error", "error_code" => expected_code }, response.parsed_body)
    end
  end

  private

  def with_search_result(result)
    service = Object.new
    service.define_singleton_method(:call) { result }

    with_search_service(service) { yield }
  end

  def with_search_service(service)
    search_service_class = Stores::AiAutofill::SearchService
    original_constructor = search_service_class.method(:new)
    search_service_class.define_singleton_method(:new) { |**| service }

    yield
  ensure
    search_service_class.define_singleton_method(:new, original_constructor)
  end

  def partial_result
    fields = Stores::AiAutofill::SearchService::FIELD_NAMES.index_with { nil }
    fields["area"] = "渋谷区"
    Stores::AiAutofill::SearchService::Result.new(
      status: "partial",
      fields:,
      field_sources: { "area" => [ "https://example.com/store" ] },
      sources: [ { "title" => "店舗公式", "url" => "https://example.com/store" } ]
    )
  end
end
