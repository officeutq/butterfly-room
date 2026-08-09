# frozen_string_literal: true

require "google/apis/sheets_v4"

module LpAnalytics
  module Sheets
    class ClientFactory
      SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

      def initialize(secrets_client: nil, retry_policy: RetryPolicy.new, service_class: Google::Apis::SheetsV4::SheetsService)
        @secrets_client = secrets_client
        @retry_policy = retry_policy
        @service_class = service_class
      end

      def call(settings)
        settings.validate!
        authorization = CredentialsProvider.new(
          secret_id: settings.credentials_secret_id,
          region: settings.region,
          scope: SCOPE,
          secrets_client: secrets_client,
          retry_policy: retry_policy
        ).call
        service = service_class.new
        service.authorization = authorization

        Client.new(
          service: service,
          spreadsheet_id: settings.spreadsheet_id,
          retry_policy: retry_policy
        )
      end

      private

      attr_reader :secrets_client, :retry_policy, :service_class
    end
  end
end
