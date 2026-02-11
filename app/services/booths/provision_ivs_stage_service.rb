# frozen_string_literal: true

module Booths
  class ProvisionIvsStageService
    class Error < StandardError; end
    class StageProvisionFailed < Error; end

    DEFAULT_PREFIX = "br".freeze

    def initialize(booth:, ivs_client: Ivs::Client.new)
      @booth = booth
      @ivs_client = ivs_client
    end

    # NOTE:
    # IVS Stage は「booth 固定」。stream_session 単位で create_stage しない。
    # Stage 作成はこのサービス（Booths::ProvisionIvsStageService）に集約する。
    # viewer/publisher token 発行などの経路から accidental create が起きないようにする。

    def call!
      @booth.with_lock do
        return @booth.ivs_stage_arn if @booth.ivs_stage_arn.present?

        arn = @ivs_client.create_stage!(
          name: stage_name,
          tags: stage_tags
        )

        raise StageProvisionFailed, "create_stage returned blank arn" if arn.blank?

        @booth.update!(ivs_stage_arn: arn)
        arn
      end
    rescue Aws::Errors::ServiceError => e
      raise StageProvisionFailed, "IVS create_stage failed: #{e.class} #{e.message}"
    end

    private

    def stage_name
      # 例: br-prod-store-1-booth-3
      "#{name_prefix}-store-#{@booth.store_id}-booth-#{@booth.id}"
    end

    def name_prefix
      # 環境差は設定のみ（未設定時だけフォールバック）
      # 例: br-dev / br-prod
      ENV.fetch("IVS_STAGE_NAME_PREFIX", DEFAULT_PREFIX)
    end

    def stage_tags
      # タグは後の検索/ガベコレ/運用が超ラクになる
      {
        "app"      => "butterfly-room",
        "env"      => ENV.fetch("IVS_STAGE_ENV", name_prefix), # 任意。未設定ならprefixを流用
        "store_id" => @booth.store_id.to_s,
        "booth_id" => @booth.id.to_s
      }
    end
  end
end
