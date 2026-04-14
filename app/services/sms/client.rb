# frozen_string_literal: true

module Sms
  class Client
    class << self
      attr_writer :factory

      def build(region: default_region)
        return @factory.call(region: region) if @factory.present?

        new(region: region)
      end

      def reset_factory!
        @factory = nil
      end

      private

      def default_region
        ENV["AWS_REGION"].presence ||
          Rails.application.credentials.dig(:aws, :region) ||
          "ap-northeast-1"
      end
    end

    def initialize(region: self.class.send(:default_region))
      @client = Aws::SNS::Client.new(region: region)
    end

    def publish!(phone_number:, message:)
      @client.publish(
        phone_number: phone_number,
        message: message
      )
    end
  end
end
