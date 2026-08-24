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
    initialization_calls = []

    with_search_result(partial_result, initialization_calls:) do
      post admin_store_ai_autofill_path(@store),
           params: { store_ai_autofill: { store_name: "フォーム入力店舗", published: true } },
           as: :json
    end

    assert_response :ok
    body = response.parsed_body
    assert_equal "partial", body.fetch("status")
    assert_equal "渋谷区", body.dig("fields", "area")
    assert_equal "フォーム入力店舗", initialization_calls.sole.fetch(:store_name)
    assert_equal @store, initialization_calls.sole.fetch(:store)
    assert_equal @store_admin, initialization_calls.sole.fetch(:actor)
    assert_not initialization_calls.sole.key?(:published)
    assert_equal original_attributes, @store.reload.attributes
  end

  test "filters the AI search payload from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(
      "store_ai_autofill" => { "store_name" => "ログへ出してはいけない店舗名" }
    )

    assert_equal "[FILTERED]", filtered.fetch("store_ai_autofill")
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
    Stores::AiAutofill::SearchService::InvalidStoreNameError => [ :unprocessable_entity, "invalid_store_name" ],
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

  test "returns safe OpenAI diagnostics only in development" do
    sign_in @store_admin, scope: :user
    error = Stores::AiAutofill::ResponsesClient::RateLimitedError.new(
      "test",
      request_id: "request-429",
      openai_status: 429,
      openai_code: "rate_limit_exceeded",
      openai_type: "tokens"
    )
    service = Object.new
    service.define_singleton_method(:call) { raise error }
    with_rails_environment("development") do
      with_search_service(service) do
        post admin_store_ai_autofill_path(@store), as: :json
      end
    end

    assert_response :service_unavailable
    assert_equal(
      {
        "status" => "error",
        "error_code" => "openai_rate_limited",
        "development_diagnostics" => {
          "openai_type" => "tokens",
          "openai_code" => "rate_limit_exceeded",
          "openai_status" => "429",
          "request_id" => "request-429"
        }
      },
      response.parsed_body
    )
  end

  test "does not return OpenAI diagnostics outside development" do
    sign_in @store_admin, scope: :user
    error = Stores::AiAutofill::ResponsesClient::RateLimitedError.new(
      "test",
      request_id: "request-429",
      openai_status: 429,
      openai_code: "rate_limit_exceeded",
      openai_type: "tokens"
    )
    service = Object.new
    service.define_singleton_method(:call) { raise error }

    with_search_service(service) do
      post admin_store_ai_autofill_path(@store), as: :json
    end

    assert_response :service_unavailable
    assert_equal(
      { "status" => "error", "error_code" => "openai_rate_limited" },
      response.parsed_body
    )
  end

  private

  def with_search_result(result, initialization_calls: nil)
    service = Object.new
    service.define_singleton_method(:call) { result }

    with_search_service(service, initialization_calls:) { yield }
  end

  def with_search_service(service, initialization_calls: nil)
    search_service_class = Stores::AiAutofill::SearchService
    original_constructor = search_service_class.method(:new)
    search_service_class.define_singleton_method(:new) do |**arguments|
      initialization_calls << arguments if initialization_calls
      service
    end

    yield
  ensure
    search_service_class.define_singleton_method(:new, original_constructor)
  end

  def with_rails_environment(name)
    original_environment = Rails.method(:env)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    Rails.define_singleton_method(:env) { environment }

    yield
  ensure
    Rails.define_singleton_method(:env, original_environment)
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
