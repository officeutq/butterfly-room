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
    def initialize(actor_user:, logger: Rails.logger)
      @actor_user = actor_user
      @logger = logger
    end

    def call
      scope = Settlement.where(status: Settlement.statuses[:confirmed])

      # manual_bank の絞り込み（可能なら）
      scope = filter_manual_bank_only(scope)

      settlements = scope.order(:id).to_a
      return { ok: false, message: "対象の精算（confirmed）がありません" } if settlements.empty?

      # payout口座がない settlement はスキップ（exported移行しない）
      exportable, skipped = partition_exportable(settlements)
      return { ok: false, message: "振込先口座が設定済みの対象がありません" } if exportable.empty?

      created_exports = []
      exportable.each_slice(MAX_RECORDS_PER_FILE).with_index(1) do |slice, seq|
        created_exports << create_one_file!(slice, seq: seq)
      end

      msg =
        if skipped.empty?
          "ok"
        else
          "skipped=#{skipped.size}"
        end

      { ok: true, created_exports: created_exports, message: msg }
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
      s = NKF.nkf("-w -x -Z1 -Z4", s) # ← -x を足す
      s = s.strip.gsub(/[ ]+/, " ")
      max_len ? s.byteslice(0, max_len) : s
    end

    def filter_manual_bank_only(scope)
      return scope unless defined?(StorePayoutAccount)

      if StorePayoutAccount.respond_to?(:payout_methods) && StorePayoutAccount.payout_methods.key?("manual_bank")
        scope
          .joins("INNER JOIN store_payout_accounts spa ON spa.store_id = settlements.store_id")
          .where("spa.status = 0") # active想定（uniq partial index の where (status = 0) に合わせる）
          .where("spa.payout_method = ?", StorePayoutAccount.payout_methods[:manual_bank])
          .distinct
      else
        scope
      end
    end

    def partition_exportable(settlements)
      exportable = []
      skipped = []

      settlements.each do |s|
        account = active_payout_account_for(s.store_id)
        if account.blank?
          skipped << { settlement_id: s.id, reason: "no_payout_account" }
          next
        end

        exportable << s
      end

      [ exportable, skipped ]
    end

    def create_one_file!(settlements, seq:)
      Time.use_zone(ZONE) do
        today = Time.zone.today
        mmdd = today.strftime("%m%d")

        payer = payer_info!
        total_amount = settlements.sum(&:store_share_yen)
        record_count = settlements.size

        csv_string = build_csv_string(mmdd:, payer:, settlements:, total_amount:, record_count:)

        export = SettlementExport.create!(
          format: :sbi_furikomi_csv,
          generated_by_user: @actor_user,
          file_seq: seq,
          record_count: record_count,
          total_amount_yen: total_amount
        )

        filename = "furikomi_#{today.strftime('%Y%m%d')}_#{seq.to_s.rjust(2, '0')}.csv"
        export.file.attach(
          io: StringIO.new(csv_string.encode(Encoding::Shift_JIS, invalid: :replace, undef: :replace, replace: "?")),
          filename: filename,
          content_type: "text/csv"
        )

        blob_key = export.file.blob.key

        # settlement を exported に更新（スナップショットも埋める）
        ApplicationRecord.transaction do
          settlements.each do |s|
            apply_export_snapshot!(s, export:, blob_key:)
          end
        end

        export
      end
    end

    def build_csv_string(mmdd:, payer:, settlements:, total_amount:, record_count:)
      CSV.generate(force_quotes: false) do |csv|
        # 1) ヘッダ
        csv << [
          "1",                 # データ区分
          "21",                # 種別コード（総合振込）
          "0",                 # コード区分（0:JIS）※省略可だが明示
          payer[:client_code], # 振込依頼人コード（10桁）
          to_hankaku(payer[:client_name]), # 振込依頼人名（カナ推奨）
          mmdd,                # 取組日
          payer[:bank_code],   # 仕向銀行番号（0038）
          to_hankaku(payer[:bank_name]),   # 仕向銀行名
          payer[:branch_code], # 仕向支店番号
          to_hankaku(payer[:branch_name]), # 仕向支店名
          payer[:account_type], # 預金種目（依頼人） 1:普通
          payer[:account_number], # 口座番号（依頼人）
          ""                   # ダミー（省略可）
        ]

        # 2) データ
        settlements.each do |s|
          acct = active_payout_account_for(s.store_id)
          # 受取人名は「口座名義カナ」を優先（なければ store.name をカナ化せずそのまま）
          payee_name = acct&.account_holder_kana.to_s.presence || s.store.name.to_s

          csv << [
            "2",                     # データ区分
            acct.bank_code.to_s,     # 被仕向銀行番号
            "",                      # 被仕向銀行名（省略可）
            acct.branch_code.to_s,   # 被仕向支店番号
            "",                      # 被仕向支店名（省略可）
            "0000",                  # 統一手形交換所番号（未使用）
            normalize_account_type(acct.account_type), # 預金種目
            acct.account_number.to_s, # 口座番号
            to_hankaku(payee_name, max_len: 40),  # 受取人名
            s.store_share_yen.to_i,  # 振込金額
            "1",                     # 新規コード（1固定：第1回扱い）
            "",                      # 顧客コード1（省略可）
            "",                      # 顧客コード2（省略可）
            "7",                     # 振込指定区分（7:テレ振込）
            "",                      # 識別表示（省略=スペース扱い）
            ""                       # ダミー（省略可）
          ]
        end

        # 3) トレーラ
        csv << [
          "8",
          record_count.to_i,
          total_amount.to_i,
          "" # ダミー（省略可）
        ]

        # 4) エンド
        csv << [
          "9",
          "" # ダミー（省略可）
        ]
      end
    end

    def apply_export_snapshot!(settlement, export:, blob_key:)
      acct = active_payout_account_for(settlement.store_id)
      raise "no payout account store_id=#{settlement.store_id}" if acct.blank?

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

    def active_payout_account_for(store_id)
      return nil unless defined?(StorePayoutAccount)

      # schema.rb の uniq partial index: where (status = 0) に合わせる（0=active想定）
      StorePayoutAccount.where(store_id: store_id, status: 0).order(id: :desc).first
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
      v = value.to_s
      return v if %w[1 2 4 9].include?(v)
      "1"
    end

    def map_account_type_to_settlement(value)
      # Settlement enum :payout_account_type, { ordinary: 0, current: 1 }
      v = value.to_s
      return Settlement.payout_account_types[:current] if v == "2"
      Settlement.payout_account_types[:ordinary]
    end
  end
end
