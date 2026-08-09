# frozen_string_literal: true

require "test_helper"
require "openssl"

class LpAnalytics::Sheets::CredentialsProviderTest < ActiveSupport::TestCase
  Response = Struct.new(:secret_string, keyword_init: true)

  test "指定Secretからservice account認証を生成する" do
    requested_ids = []
    secrets_client = Object.new
    secret_json = service_account_json
    secrets_client.define_singleton_method(:get_secret_value) do |secret_id:|
      requested_ids << secret_id
      Response.new(secret_string: secret_json)
    end

    credentials = LpAnalytics::Sheets::CredentialsProvider.new(
      secret_id: "dummy-secret-id",
      region: "ap-northeast-1",
      scope: "https://www.googleapis.com/auth/spreadsheets",
      secrets_client: secrets_client
    ).call

    assert_instance_of Google::Auth::ServiceAccountCredentials, credentials
    assert_equal [ "dummy-secret-id" ], requested_ids
  end

  test "不正なcredential JSONを秘密値を含めずに拒否する" do
    secrets_client = Object.new
    secrets_client.define_singleton_method(:get_secret_value) do |secret_id:|
      Response.new(secret_string: "private-value-#{secret_id}")
    end

    error = assert_raises(LpAnalytics::Sheets::CredentialsProvider::CredentialsError) do
      LpAnalytics::Sheets::CredentialsProvider.new(
        secret_id: "dummy-secret-id",
        region: "ap-northeast-1",
        scope: "scope",
        secrets_client: secrets_client
      ).call
    end

    refute_includes error.message, "private-value"
    refute_includes error.message, "dummy-secret-id"
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
      auth_uri: "https://accounts.google.com/o/oauth2/auth",
      token_uri: "https://oauth2.googleapis.com/token",
      auth_provider_x509_cert_url: "https://www.googleapis.com/oauth2/v1/certs",
      client_x509_cert_url: "https://www.googleapis.com/robot/v1/metadata/x509/dummy",
      universe_domain: "googleapis.com"
    )
  end
end
