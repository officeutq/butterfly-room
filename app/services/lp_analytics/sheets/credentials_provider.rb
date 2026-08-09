# frozen_string_literal: true

require "aws-sdk-secretsmanager"
require "googleauth"
require "json"
require "openssl"
require "stringio"

module LpAnalytics
  module Sheets
    class CredentialsProvider
      class CredentialsError < StandardError; end

      SERVICE_ACCOUNT_KEYS = %w[
        type
        project_id
        private_key_id
        private_key
        client_email
        client_id
        auth_uri
        token_uri
        auth_provider_x509_cert_url
        client_x509_cert_url
        universe_domain
      ].freeze
      REQUIRED_KEYS = %w[type project_id private_key private_key_id client_email client_id token_uri].freeze
      TOKEN_URI = "https://oauth2.googleapis.com/token"

      def initialize(secret_id:, region:, scope:, secrets_client: nil, retry_policy: RetryPolicy.new)
        @secret_id = secret_id
        @region = region
        @scope = scope
        @secrets_client = secrets_client
        @retry_policy = retry_policy
      end

      def call
        secret_string = retry_policy.call do
          client.get_secret_value(secret_id: secret_id).secret_string
        end
        attributes = validated_service_account(JSON.parse(secret_string.to_s))
        json_io = StringIO.new(JSON.generate(attributes))

        Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: json_io, scope: scope)
      rescue JSON::ParserError, KeyError, ArgumentError, OpenSSL::PKey::PKeyError
        raise CredentialsError, "service account credentials are invalid"
      ensure
        secret_string = nil
        json_io&.close
      end

      private

      attr_reader :secret_id, :region, :scope, :secrets_client, :retry_policy

      def client
        secrets_client || Aws::SecretsManager::Client.new(region: region)
      end

      def validated_service_account(attributes)
        raise CredentialsError, "service account credentials are invalid" unless attributes.is_a?(Hash)
        raise CredentialsError, "service account credentials are invalid" unless attributes["type"] == "service_account"
        raise CredentialsError, "service account credentials are invalid" unless attributes["token_uri"] == TOKEN_URI
        raise CredentialsError, "service account credentials are invalid" unless REQUIRED_KEYS.all? { |key| attributes[key].is_a?(String) && attributes[key].present? }
        raise CredentialsError, "service account credentials are invalid" unless attributes["client_email"].end_with?(".gserviceaccount.com")
        raise CredentialsError, "service account credentials are invalid" unless attributes["private_key"].start_with?("-----BEGIN PRIVATE KEY-----")

        attributes.slice(*SERVICE_ACCOUNT_KEYS)
      end
    end
  end
end
