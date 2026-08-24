# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::ResponsesClientTest < ActiveSupport::TestCase
  FakeResponses = Struct.new(:response, :calls) do
    def create(**params)
      calls << params
      raise response if response.is_a?(Exception)

      response
    end
  end

  FakeClient = Struct.new(:responses)

  setup do
    @settings = Stores::AiAutofill::Settings.new(api_key: "test-key", model: "gpt-5.6-terra")
  end

  test "sends one Responses API request with web search and structured outputs" do
    source_url = "https://example.com/store"
    payload = { "match_status" => "not_found" }
    calls = []
    response = completed_response(payload:, source_url:)
    client = build_client(response, calls:)

    result = client.call(
      store_search_input: { store_name: "店舗A" },
      system_prompt: "system",
      response_schema: { type: "object" }
    )

    assert_equal 1, calls.size
    request = calls.first
    assert_equal "gpt-5.6-terra", request[:model]
    assert_equal({ effort: :medium }, request[:reasoning])
    assert_equal [ { type: :web_search } ], request[:tools]
    assert_equal :required, request[:tool_choice]
    assert_equal [ "web_search_call.action.sources" ], request[:include]
    assert_equal false, request[:store]
    assert_equal({ timeout: 45, max_retries: 0 }, request[:request_options])
    assert_equal "system", request[:input].first[:content]
    assert_equal({ "store_name" => "店舗A" }, JSON.parse(request[:input].last[:content]))
    assert_equal :json_schema, request.dig(:text, :format, :type)
    assert_equal true, request.dig(:text, :format, :strict)

    assert_equal payload, result.data
    assert_equal "request-123", result.request_id
    assert_equal [ { "url" => source_url, "title" => "店舗公式" } ], result.sources
  end

  test "rejects incomplete responses" do
    response = completed_response(payload: {}, source_url: "https://example.com").merge(
      status: "incomplete",
      incomplete_details: { reason: "max_output_tokens" }
    )

    assert_raises(Stores::AiAutofill::ResponsesClient::InvalidResponseError) do
      build_client(response).call(
        store_search_input: {},
        system_prompt: "system",
        response_schema: {}
      )
    end
  end

  test "rejects refusals" do
    response = completed_response(payload: {}, source_url: "https://example.com")
    response[:output] = [
      {
        type: :message,
        content: [ { type: :refusal, refusal: "refused" } ]
      }
    ]

    assert_raises(Stores::AiAutofill::ResponsesClient::InvalidResponseError) do
      build_client(response).call(
        store_search_input: {},
        system_prompt: "system",
        response_schema: {}
      )
    end
  end

  test "maps OpenAI timeout errors" do
    error = OpenAI::Errors::APITimeoutError.new(url: URI("https://api.openai.com/v1/responses"))

    assert_raises(Stores::AiAutofill::ResponsesClient::TimeoutError) do
      build_client(error).call(
        store_search_input: {},
        system_prompt: "system",
        response_schema: {}
      )
    end
  end

  test "preserves safe OpenAI rate limit diagnostics" do
    error = OpenAI::Errors::RateLimitError.new(
      url: URI("https://api.openai.com/v1/responses"),
      status: 429,
      headers: { "x-request-id" => "request-429" },
      body: {
        code: "rate_limit_exceeded",
        type: "tokens"
      },
      request: nil,
      response: nil
    )

    raised = assert_raises(Stores::AiAutofill::ResponsesClient::RateLimitedError) do
      build_client(error).call(
        store_search_input: {},
        system_prompt: "system",
        response_schema: {}
      )
    end

    assert_equal "request-429", raised.request_id
    assert_equal 429, raised.openai_status
    assert_equal "rate_limit_exceeded", raised.openai_code
    assert_equal "tokens", raised.openai_type
  end

  private

  def build_client(response, calls: [])
    fake_responses = FakeResponses.new(response, calls)
    Stores::AiAutofill::ResponsesClient.new(
      settings: @settings,
      client: FakeClient.new(fake_responses)
    )
  end

  def completed_response(payload:, source_url:)
    {
      status: :completed,
      incomplete_details: nil,
      _request_id: "request-123",
      output: [
        {
          type: :web_search_call,
          action: {
            type: :search,
            sources: [ { type: :url, url: source_url } ]
          }
        },
        {
          type: :message,
          content: [
            {
              type: :output_text,
              text: JSON.generate(payload),
              annotations: [
                {
                  type: :url_citation,
                  url: source_url,
                  title: "店舗公式"
                }
              ]
            }
          ]
        }
      ]
    }
  end
end
