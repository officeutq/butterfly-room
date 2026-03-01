# frozen_string_literal: true

require "csv"
require "nkf"

module Settlements
  class SbiFurikomiCsvExportService
    ZONE = "Asia/Tokyo"
    MAX_RECORDS_PER_FILE = 9_999

    # 住信SBI（総合振込）CSV：EDI通知しない場合
    # レコード構成：ヘッダ(1) / データ(2)×N / トレーラ(8) / エンド(9)
    #
    # 振込依頼人（支払元）情報は ENV で固定（後でDB化想定）
    #
    # ENV例:
    #   SOUTOKU_FURIKOMI_CLIENT_CODE=2000000001  (10桁)
    #   SOUTOKU_FURIKOMI_CLIENT_NAME=ﾊﾞﾀﾌﾗｲﾍﾞ  (半角ｶﾅ)
    #   SOUTOKU_FURIKOMI_BANK_CODE=0038
    #   SOUTOKU_FURIKOMI_BANK_NAME=ｽﾐｼﾝSBIﾈｯﾄ
    #   SOUTOKU_FURIKOMI_BRANCH_CODE=106
    #   SOUTOKU_FURIKOMI_BRANCH_NAME=ﾎﾝﾃﾝ
    #   SOUTOKU_FURIKOMI_ACCOUNT_TYPE=1         (1:普通)
    #   SOUTOKU_FURIKOMI_ACCOUNT_NUMBER=1234567
    #
    def initialize(actor_user:, settlements:, logger: Rails.logger)
      @actor_user = actor_user
      @settlements = Array(settlements)
      @logger = logger
    end

    def call
      return { ok: false, message: "対象の精算がありません" } if @settlements.empty?

      # guard: confirmed only
      not_confirmed = @settlements.reject(&:confirmed?)
      return { ok: false, message: "confirmed 以外が含まれています（id=#{not_confirmed.map(&:id).join(',')}）" } if not_confirmed.any?

      # guard: 1 file only
      if @settlements.size > MAX_RECORDS_PER_FILE
        return { ok: false, message: "1ファイル最大#{MAX_RECORDS_PER_FILE}件です（選択=#{@settlements.size}件）" }
      end

      # manual_bank only & must have active payout account
      accounts_by_store_id = fetch_active_manual_bank_accounts(@settlements.map(&:store_id).uniq)

      missing = @settlements.select { |s| accounts_by_store_id[s.store_id].blank? }
      return { ok: false, message: "振込先口座（manual_bank）が未設定の精算が含まれています（id=#{missing.map(&:id).join(',')}）" } if missing.any?

      export = create_one_file!(@settlements, accounts_by_store_id: accounts_by_store_id)

      { ok: true, created_exports: [ export ], message: "ok" }
    rescue => e
      @logger.error("[SbiFurikomiCsvExport] failed #{e.class}: #{e.message}")
      raise
    end

    private

    # 住信SBIの「半角」寄せ（最低限）
    # - 全角スペース → 半角スペース
    # - 全角カナ → 半角カナ
    # - 全角英数 → 半角英数
    def to_hankaku(str, max_len: nil)
      s = str.to_s
      s = s.tr("　", " ")
      s = NKF.nkf("-w -x -Z1 -Z4", s)
      s = s.strip.gsub(/[ ]+/, " ")
      max_len ? s.byteslice(0, max_len) : s
    end

    def fetch_active_manual_bank_accounts(store_ids)
      return {} unless defined?(StorePayoutAccount)

      StorePayoutAccount
        .where(store_id: store_ids, status: StorePayoutAccount.statuses[:active], payout_method: StorePayoutAccount.payout_methods[:manual_bank])
        .order(id: :desc)
        .group_by(&:store_id)
        .transform_values { |arr| arr.first }
    end

    def create_one_file!(settlements, accounts_by_store_id:)
      Time.use_zone(ZONE) do
        today = Time.zone.today
        mmdd = today.strftime("%m%d")

        payer = payer_info!
        total_amount = settlements.sum(&:store_share_yen)
        record_count = settlements.size

        csv_string = build_csv_string(
          mmdd: mmdd,
          payer: payer,
          settlements: settlements,
          accounts_by_store_id: accounts_by_store_id,
          total_amount: total_amount,
          record_count: record_count
        )

        export = SettlementExport.create!(
          format: :sbi_furikomi_csv,
          generated_by_user: @actor_user,
          file_seq: 1,
          record_count: record_count,
          total_amount_yen: total_amount
        )

        filename = "furikomi_#{today.strftime('%Y%m%d')}_01.csv"
        export.file.attach(
          io: StringIO.new(csv_string.encode(Encoding::Shift_JIS, invalid: :replace, undef: :replace, replace: "?")),
          filename: filename,
          content_type: "text/csv"
        )

        blob_key = export.file.blob.key

        ApplicationRecord.transaction do
          settlements.each do |s|
            acct = accounts_by_store_id.fetch(s.store_id)
            apply_export_snapshot!(s, acct: acct, blob_key: blob_key)
            s.settlement_events.create!(
              actor_user: @actor_user,
              action: :exported,
              metadata: { export_id: export.id, export_blob_key: blob_key }
            )
          end
        end

        export
      end
    end

    def build_csv_string(mmdd:, payer:, settlements:, accounts_by_store_id:, total_amount:, record_count:)
      CSV.generate(force_quotes: false) do |csv|
        csv << [
          "1",
          "21",
          "0",
          payer[:client_code],
          to_hankaku(payer[:client_name]),
          mmdd,
          payer[:bank_code],
          to_hankaku(payer[:bank_name]),
          payer[:branch_code],
          to_hankaku(payer[:branch_name]),
          payer[:account_type],
          payer[:account_number],
          ""
        ]

        settlements.each do |s|
          acct = accounts_by_store_id.fetch(s.store_id)
          payee_name = acct.account_holder_kana.to_s.presence || s.store.name.to_s

          csv << [
            "2",
            acct.bank_code.to_s,
            "",
            acct.branch_code.to_s,
            "",
            "0000",
            normalize_account_type(acct.account_type),
            acct.account_number.to_s,
            to_hankaku(payee_name, max_len: 40),
            s.store_share_yen.to_i,
            "1",
            "",
            "",
            "7",
            "",
            ""
          ]
        end

        csv << [ "8", record_count.to_i, total_amount.to_i, "" ]
        csv << [ "9", "" ]
      end
    end

    def apply_export_snapshot!(settlement, acct:, blob_key:)
      settlement.update!(
        status: :exported,
        exported_at: Time.use_zone(ZONE) { Time.zone.now },
        exported_by_user: @actor_user,
        export_format: "sbi_furikomi_csv",
        export_file_key: blob_key,

        payout_bank_code: acct.bank_code,
        payout_branch_code: acct.branch_code,
        payout_account_type: map_account_type_to_settlement(acct.account_type),
        payout_account_number: acct.account_number,
        payout_account_holder_kana: acct.account_holder_kana
      )
    end

    def payer_info!
      {
        client_code:   ENV.fetch("SOUTOKU_FURIKOMI_CLIENT_CODE"),
        client_name:   ENV.fetch("SOUTOKU_FURIKOMI_CLIENT_NAME"),
        bank_code:     ENV.fetch("SOUTOKU_FURIKOMI_BANK_CODE", "0038"),
        bank_name:     ENV.fetch("SOUTOKU_FURIKOMI_BANK_NAME", "ｽﾐｼﾝSBIﾈｯﾄ"),
        branch_code:   ENV.fetch("SOUTOKU_FURIKOMI_BRANCH_CODE"),
        branch_name:   ENV.fetch("SOUTOKU_FURIKOMI_BRANCH_NAME"),
        account_type:  ENV.fetch("SOUTOKU_FURIKOMI_ACCOUNT_TYPE", "1"),
        account_number: ENV.fetch("SOUTOKU_FURIKOMI_ACCOUNT_NUMBER")
      }
    end

    def normalize_account_type(value)
      # 住信SBI仕様: 1(普通) / 2(当座) / 4(貯蓄) / 9(その他)
      # StorePayoutAccount enum は ordinary/current なので 1/2 に寄せる
      v = value.to_s
      return v if %w[1 2 4 9].include?(v)
      "1"
    end

    def map_account_type_to_settlement(value)
      # StorePayoutAccount enum :account_type, { ordinary: 0, current: 1 }
      v = value.to_s
      return Settlement.payout_account_types[:current] if v == "current" || v == "2" || v == StorePayoutAccount.account_types[:current].to_s
      Settlement.payout_account_types[:ordinary]
    end
  end
end
