# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::SearchServiceTest < ActiveSupport::TestCase
  FakeResponsesClient = Struct.new(:result, :calls) do
    def call(**params)
      calls << params
      result
    end
  end

  RecordingLogger = Struct.new(:info_entries, :warning_entries) do
    def info(payload)
      info_entries << payload
    end

    def warn(payload)
      warning_entries << payload
    end
  end

  Actor = Data.define(:id)

  setup do
    @store = Store.create!(
      name: "店舗A",
      phone_number: "03-1234-5678",
      address: "東京都渋谷区道玄坂1-2-3"
    )
    @actor = Actor.new(id: 42)
    @source_url = "https://example.com/store/"
  end

  test "returns verified candidates and sends only the allowed store input" do
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["area"] = candidate("渋谷区")
    calls = []

    result = call_service(data, calls:)

    assert_equal "partial", result.status
    assert_equal "渋谷区", result.fields["area"]
    assert_nil result.fields["description"]
    assert_equal [ @source_url ], result.field_sources["area"]
    assert_equal [ { "title" => "店舗公式", "url" => @source_url } ], result.sources
    assert_equal 1, calls.size

    input = calls.first.fetch(:store_search_input)
    assert_equal "店舗A", input.fetch(:store_name)
    assert_equal [ :business_type_options, :store_name ], input.keys.sort
    assert_equal Store::BUSINESS_TYPE_LABELS.transform_keys(&:to_s), input.fetch(:business_type_options)
    assert_not input.key?(:id)
    assert_not input.key?(:existing)
    assert_equal %w[normalized official_alias none],
                 calls.first.dig(:response_schema, :properties, :name_match_kind, :enum)
  end

  test "uses the current form store name for the AI search input" do
    data = base_data
    data["matched_name"] = "フォーム入力店舗"
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["area"] = candidate("渋谷区")
    calls = []

    result = call_service(data, calls:, store_name: "  フォーム入力店舗  ")

    assert_equal "partial", result.status
    assert_equal "フォーム入力店舗", calls.sole.fetch(:store_search_input).fetch(:store_name)
    assert_equal "店舗A", @store.name
  end

  test "rejects a blank form store name before calling OpenAI" do
    calls = []

    assert_raises(Stores::AiAutofill::SearchService::InvalidStoreNameError) do
      call_service(base_data, calls:, store_name: "  ")
    end

    assert_empty calls
  end

  test "rejects an oversized form store name before calling OpenAI" do
    calls = []

    assert_raises(Stores::AiAutofill::SearchService::InvalidStoreNameError) do
      call_service(
        base_data,
        calls:,
        store_name: "店" * (Stores::AiAutofill::SearchService::MAX_STORE_NAME_LENGTH + 1)
      )
    end

    assert_empty calls
  end

  test "drops candidates with unverified sources and invalid social hosts" do
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["area"] = candidate("渋谷区")
    data["fields"]["description"] = candidate("概要", "https://invented.example/store")
    data["fields"]["x_url"] = candidate("https://malicious.example/account")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "渋谷区", result.fields["area"]
    assert_nil result.fields["description"]
    assert_nil result.fields["x_url"]
  end

  test "downgrades a conflicting match to ambiguous" do
    data = base_data
    data["conflicting_candidates_found"] = true
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["area"] = candidate("渋谷区")

    result = call_service(data)

    assert_equal "ambiguous", result.status
    assert result.fields.values.all?(&:nil?)
    assert_empty result.field_sources
  end

  test "logs model and guard ambiguity reasons only in development" do
    data = base_data
    data["match_status"] = "ambiguous"
    data["conflicting_candidates_found"] = true
    data["identity_evidence"] = [ official_website_evidence ]
    logger = recording_logger

    with_rails_environment("development") do
      call_service(data, logger:)
    end

    entry = logger.info_entries.sole
    assert_equal %w[model_ambiguous conflicting_candidates], entry.fetch(:ambiguity_reasons)
    assert_equal "request-123", entry.fetch(:openai_request_id)
    assert_not_includes entry.to_s, @store.name
    assert_not_includes entry.to_s, @source_url
  end

  test "logs a missing verified identity source in development" do
    data = base_data
    logger = recording_logger

    with_rails_environment("development") do
      call_service(data, logger:)
    end

    assert_equal [ "missing_identity_evidence" ], logger.info_entries.sole.fetch(:ambiguity_reasons)
  end

  test "does not log ambiguity reasons outside development" do
    data = base_data
    data["conflicting_candidates_found"] = true
    data["identity_evidence"] = [ official_website_evidence ]
    logger = recording_logger

    call_service(data, logger:)

    assert_not logger.info_entries.sole.key?(:ambiguity_reasons)
  end

  test "does not use saved identity data as search input or matching evidence" do
    @store.update!(
      phone_number: "03-9999-9999",
      address: "誤った住所",
      website_url: "https://wrong.example/store",
      x_url: "https://x.com/wrong_store"
    )
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["phone_number"] = candidate("03-1234-5678")
    calls = []

    result = call_service(data, calls:)

    assert_equal "partial", result.status
    assert_equal "03-1234-5678", result.fields["phone_number"]
    assert_not calls.first.fetch(:store_search_input).key?(:existing)
  end

  test "accepts independently verified official evidence for the same store name" do
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["website_url"] = candidate("https://example.com/store")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "https://example.com/store", result.fields["website_url"]
  end

  test "accepts source-linked phone evidence without rechecking its semantic meaning" do
    data = base_data
    data["identity_evidence"] = [ phone_evidence ]
    data["fields"]["phone_number"] = candidate("03-1234-5678")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "03-1234-5678", result.fields["phone_number"]
  end

  test "accepts the model identity decision without comparing matched names" do
    data = base_data
    data["matched_name"] = "店舗B"
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["website_url"] = candidate("https://example.com/store")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "https://example.com/store", result.fields["website_url"]
  end

  test "accepts exact store name evidence from a third-party detail page" do
    data = base_data
    data["matched_name"] = "店 舗Ａ"
    data["identity_evidence"] = [
      {
        "kind" => "other",
        "value" => "店 舗Ａ",
        "source_url" => @source_url
      }
    ]
    data["fields"]["address"] = candidate("東京都渋谷区道玄坂1-2-3")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "東京都渋谷区道玄坂1-2-3", result.fields["address"]
  end

  test "accepts kana brackets and terminal store suffix after the model matches them" do
    data = base_data
    data["matched_name"] = "メイドリーミン 天神西通り店"
    data["identity_evidence"] = [
      {
        "kind" => "other",
        "value" => "メイドリーミン 天神西通り店",
        "source_url" => @source_url
      }
    ]
    data["fields"]["address"] = candidate("福岡県福岡市中央区天神2-7-22")

    result = call_service(data, store_name: "めいどりーみん（天神西通り）")

    assert_equal "partial", result.status
    assert_equal "福岡県福岡市中央区天神2-7-22", result.fields["address"]
  end

  test "accepts an official cross-script alias with source-linked evidence" do
    data = base_data
    data["matched_name"] = "maidreamin Tenjin Nishi-dori"
    data["name_match_kind"] = "official_alias"
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["address"] = candidate("福岡県福岡市中央区天神2-7-22")

    result = call_service(data, store_name: "めいどりーみん 天神西通り店")

    assert_equal "partial", result.status
    assert_equal "福岡県福岡市中央区天神2-7-22", result.fields["address"]
  end

  test "accepts a cross-script alias supported by source-linked third-party evidence" do
    data = base_data
    data["matched_name"] = "maidreamin Tenjin Nishi-dori"
    data["name_match_kind"] = "official_alias"
    data["identity_evidence"] = [
      {
        "kind" => "other",
        "value" => "maidreamin Tenjin Nishi-dori",
        "source_url" => @source_url
      }
    ]
    data["fields"]["address"] = candidate("福岡県福岡市中央区天神2-7-22")

    result = call_service(data, store_name: "めいどりーみん 天神西通り店")

    assert_equal "partial", result.status
    assert_equal "福岡県福岡市中央区天神2-7-22", result.fields["address"]
  end

  test "does not use name match kind as an application acceptance guard" do
    data = base_data
    data["name_match_kind"] = "none"
    data["identity_evidence"] = [ official_website_evidence ]
    data["fields"]["area"] = candidate("渋谷区")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "渋谷区", result.fields["area"]
  end

  test "instructs the model to distinguish another branch from an unresolved candidate" do
    calls = []
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]

    call_service(data, calls:)

    prompt = calls.sole.fetch(:system_prompt)
    assert_includes prompt, "チェーン内の別支店が存在するだけでは競合候補にしません"
    assert_includes prompt, "公開情報から同じ店舗または支店と判断できる場合はofficial_alias"
  end

  test "accepts source-linked third-party evidence without comparing its store name" do
    data = base_data
    data["matched_name"] = "店舗B"
    data["identity_evidence"] = [
      {
        "kind" => "other",
        "value" => "店舗B",
        "source_url" => @source_url
      }
    ]
    data["fields"]["address"] = candidate("東京都渋谷区道玄坂1-2-3")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "東京都渋谷区道玄坂1-2-3", result.fields["address"]
  end

  test "accepts any source-linked identity evidence after the model matches the store" do
    data = base_data
    data["identity_evidence"] = [
      {
        "kind" => "other",
        "value" => "店舗紹介ページ",
        "source_url" => @source_url
      }
    ]
    data["fields"]["area"] = candidate("渋谷区")

    result = call_service(data)

    assert_equal "partial", result.status
    assert_equal "渋谷区", result.fields["area"]
  end

  test "returns success only when all eleven fields are valid" do
    data = base_data
    data["identity_evidence"] = [ official_website_evidence ]
    values = {
      "description" => "確認できた店舗概要",
      "area" => "渋谷区",
      "business_type" => "girls_bar",
      "address" => "東京都渋谷区道玄坂1-2-3",
      "phone_number" => "03-1234-5678",
      "business_hours" => "20:00〜LAST",
      "website_url" => "https://example.com/store",
      "x_url" => "https://x.com/store_a",
      "instagram_url" => "https://www.instagram.com/store_a",
      "tiktok_url" => "https://www.tiktok.com/@store_a",
      "youtube_url" => "https://www.youtube.com/@store_a"
    }
    values.each { |field, value| data["fields"][field] = candidate(value) }

    result = call_service(data)

    assert_equal "success", result.status
    assert_equal values, result.fields
  end

  test "discards every candidate when the API reports not found" do
    data = base_data
    data["match_status"] = "not_found"
    data["fields"]["area"] = candidate("渋谷区")

    result = call_service(data)

    assert_equal "not_found", result.status
    assert result.fields.values.all?(&:nil?)
  end

  test "rejects malformed structured output" do
    data = base_data
    data["fields"].delete("area")

    assert_raises(Stores::AiAutofill::ResponsesClient::InvalidResponseError) do
      call_service(data)
    end
  end

  private

  def call_service(data, calls: [], store_name: @store.name, logger: Logger.new(IO::NULL))
    api_result = Stores::AiAutofill::ResponsesClient::Result.new(
      data:,
      sources: [ { "title" => "店舗公式", "url" => @source_url } ],
      request_id: "request-123",
      model: "gpt-5.6-terra"
    )
    fake_client = FakeResponsesClient.new(api_result, calls)

    Stores::AiAutofill::SearchService.new(
      store: @store,
      actor: @actor,
      store_name:,
      responses_client: fake_client,
      logger:
    ).call
  end

  def recording_logger
    RecordingLogger.new([], [])
  end

  def with_rails_environment(name)
    original_environment = Rails.method(:env)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    Rails.define_singleton_method(:env) { environment }

    yield
  ensure
    Rails.define_singleton_method(:env, original_environment)
  end

  def base_data
    {
      "match_status" => "matched",
      "matched_name" => "店舗A",
      "name_match_kind" => "normalized",
      "conflicting_candidates_found" => false,
      "identity_evidence" => [],
      "fields" => Stores::AiAutofill::SearchService::FIELD_NAMES.index_with do
        { "value" => nil, "source_urls" => [] }
      end
    }
  end

  def phone_evidence
    {
      "kind" => "phone_number",
      "value" => "0312345678",
      "source_url" => @source_url
    }
  end

  def official_website_evidence
    {
      "kind" => "official_website",
      "value" => "https://example.com/store",
      "source_url" => @source_url
    }
  end

  def candidate(value, source_url = @source_url)
    { "value" => value, "source_urls" => [ source_url ] }
  end
end
