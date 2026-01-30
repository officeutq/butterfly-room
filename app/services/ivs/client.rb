# frozen_string_literal: true

module Ivs
  class Client
    def initialize(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))
      @client = Aws::IVSRealTime::Client.new(region: region)
    end

    # returns stage arn
    def create_stage!(name:)
      resp = @client.create_stage(name: name)
      resp.stage.arn
    end
  end
end
