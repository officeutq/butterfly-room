# frozen_string_literal: true

require "json"
require "openai"

module Stores
  module AiAutofill
    class ResponsesClient
      Result = Data.define(:data, :sources, :request_id, :model)

      class Error < StandardError
        attr_reader :request_id, :openai_status, :openai_code, :openai_type

        def initialize(
          message = nil,
          request_id: nil,
          openai_status: nil,
          openai_code: nil,
          openai_type: nil
        )
          @request_id = request_id
          @openai_status = openai_status
          @openai_code = openai_code
          @openai_type = openai_type
          super(message)
        end
      end

      class RateLimitedError < Error; end
      class TimeoutError < Error; end
      class UnavailableError < Error; end
      class InvalidResponseError < Error; end

      def initialize(settings: Settings.from_env, client: nil)
        @settings = settings
        @client = client || OpenAI::Client.new(api_key: settings.api_key)
      end

      def call(store_search_input:, system_prompt:, response_schema:)
        response = @client.responses.create(
          model: @settings.model,
          reasoning: { effort: :medium },
          tools: [ { type: :web_search } ],
          tool_choice: :required,
          include: [ "web_search_call.action.sources" ],
          input: [
            { role: :system, content: system_prompt },
            { role: :user, content: JSON.generate(store_search_input) }
          ],
          text: {
            format: {
              type: :json_schema,
              name: "store_ai_autofill",
              strict: true,
              schema: response_schema
            }
          },
          store: false,
          request_options: {
            timeout: 45,
            max_retries: 0
          }
        )

        normalize_response(response)
      rescue OpenAI::Errors::RateLimitError => error
        raise RateLimitedError.new(
          "OpenAI rate limit exceeded",
          request_id: error.request_id,
          openai_status: error.status,
          openai_code: error.code,
          openai_type: error.type
        )
      rescue OpenAI::Errors::APITimeoutError => error
        raise TimeoutError.new("OpenAI request timed out", request_id: error.request_id)
      rescue OpenAI::Errors::APIConnectionError => error
        raise UnavailableError.new("OpenAI connection failed", request_id: error.request_id)
      rescue OpenAI::Errors::APIStatusError => error
        raise UnavailableError.new(
          "OpenAI request failed",
          request_id: error.request_id,
          openai_status: error.status,
          openai_code: error.code,
          openai_type: error.type
        )
      rescue JSON::ParserError, TypeError, KeyError => error
        raise InvalidResponseError, error.class.name
      end

      private

      def normalize_response(response)
        request_id = attribute(response, :_request_id)
        status = attribute(response, :status).to_s
        incomplete_details = attribute(response, :incomplete_details)
        output = Array(attribute(response, :output))

        if status != "completed" || incomplete_details.present? || refusal?(output)
          raise InvalidResponseError.new("OpenAI response was incomplete", request_id:)
        end

        output_text = if response.respond_to?(:output_text)
          response.output_text
        else
          output_text_from(output)
        end
        raise InvalidResponseError.new("OpenAI response did not contain output text", request_id:) if output_text.blank?

        Result.new(
          data: JSON.parse(output_text),
          sources: extract_sources(output),
          request_id:,
          model: @settings.model
        )
      rescue JSON::ParserError, TypeError => error
        raise InvalidResponseError.new(error.class.name, request_id:)
      end

      def refusal?(output)
        output.any? do |item|
          next false unless attribute(item, :type).to_s == "message"

          Array(attribute(item, :content)).any? do |content|
            attribute(content, :type).to_s == "refusal"
          end
        end
      end

      def output_text_from(output)
        output.filter_map do |item|
          next unless attribute(item, :type).to_s == "message"

          Array(attribute(item, :content)).filter_map do |content|
            attribute(content, :text) if attribute(content, :type).to_s == "output_text"
          end.join
        end.join
      end

      def extract_sources(output)
        titles = citation_titles(output)

        output.flat_map do |item|
          next [] unless attribute(item, :type).to_s == "web_search_call"

          action = attribute(item, :action)
          next [] unless attribute(action, :type).to_s == "search"

          Array(attribute(action, :sources)).filter_map do |source|
            url = attribute(source, :url).to_s
            next if url.blank?

            { "url" => url, "title" => titles[url].presence }
          end
        end
      end

      def citation_titles(output)
        output.each_with_object({}) do |item, titles|
          next unless attribute(item, :type).to_s == "message"

          Array(attribute(item, :content)).each do |content|
            Array(attribute(content, :annotations)).each do |annotation|
              next unless attribute(annotation, :type).to_s == "url_citation"

              url = attribute(annotation, :url).to_s
              title = attribute(annotation, :title).to_s
              titles[url] ||= title if url.present? && title.present?
            end
          end
        end
      end

      def attribute(object, name)
        return if object.nil?
        return object.public_send(name) if object.respond_to?(name)
        object[name] || object[name.to_s] if object.respond_to?(:[])
      end
    end
  end
end
