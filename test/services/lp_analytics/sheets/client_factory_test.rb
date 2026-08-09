# frozen_string_literal: true

require "test_helper"
require "openssl"

class LpAnalytics::Sheets::ClientFactoryTest < ActiveSupport::TestCase
  Response = Struct.new(:secret_string, keyword_init: true)
  ValuesResponse = Struct.new(:values, keyword_init: true)

  test "指定環境のSecretとSpreadsheetだけをclientへ渡す" do
    requested_secret_ids = []
    secrets_client = Object.new
    secret_json = service_account_json
    secrets_client.define_singleton_method(:get_secret_value) do |secret_id:|
      requested_secret_ids << secret_id
      Response.new(secret_string: secret_json)
    end
    service_class = Class.new do
      attr_accessor :authorization
      attr_reader :read_spreadsheet_ids

      def initialize
        @read_spreadsheet_ids = []
      end

      def get_spreadsheet_values(spreadsheet_id, _range)
        read_spreadsheet_ids << spreadsheet_id
        ValuesResponse.new(values: [])
      end
    end
    settings = LpAnalytics::Sheets::Settings.new(
      enabled: false,
      region: "ap-northeast-1",
      spreadsheet_id: "staging-dummy-spreadsheet",
      worksheet_name: "daily_raw",
      credentials_secret_id: "staging-dummy-secret",
      rails_environment: "production"
    )
    factory = LpAnalytics::Sheets::ClientFactory.new(
      secrets_client: secrets_client,
      service_class: service_class
    )

    client = factory.call(settings)
    client.read_values("'daily_raw'!A:Y")

    assert_equal [ "staging-dummy-secret" ], requested_secret_ids
    service = client.instance_variable_get(:@service)
    assert_equal [ "staging-dummy-spreadsheet" ], service.read_spreadsheet_ids
    assert_instance_of Google::Auth::ServiceAccountCredentials, service.authorization
  end

  private

  def service_account_json
    key = OpenSSL::PKey::RSA.new(2048)
    JSON.generate(
      type: "service_account",
      project_id: "dummy-project",
      private_key_id: "dummy-key-id",
      private_key: key.private_to_pem,
      client_email: "dummy@dummy-project.iam.gserviceaccount.com",
      client_id: "000000000000000000000",
      token_uri: "https://oauth2.googleapis.com/token"
    )
  end
end
