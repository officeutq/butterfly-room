# frozen_string_literal: true

module PayoutAccounts
  class JpBankConverter
    # ゆうちょ銀行の「記号・番号」から、他金融機関からの振込用情報へ変換する。
    #
    # 参考:
    # - ゆうちょ銀行「記号・番号から振込用の店名・預金種目・口座番号への変換の公式」
    # - ゆうちょ銀行「ゆうちょ口座と他の金融機関口座間の送金」
    #
    # 前提:
    # - 他金融機関からゆうちょ銀行へ振り込む場合、記号・番号のままでは振込できない。
    # - 振込用の「店名・預金種目・口座番号」へ変換する必要がある。
    # - ゆうちょ銀行の金融機関コードは 9900。
    #
    # Phase1で扱う対象:
    # - 総合口座・通常貯金・通常貯蓄貯金
    # - 記号が 1 から始まる口座
    #
    # 変換ルール:
    # - 記号は5桁。
    # - 記号の2〜3桁目に「8」を付けた3桁を店番とする。
    #   例: 記号 11940 -> 店番 198
    # - 預金種目は「普通」とする。
    # - 番号は2〜8桁。
    # - 番号の末尾1桁を除いたものを振込用口座番号とする。
    # - 振込用口座番号が7桁未満の場合は、左側を0で埋めて7桁にする。
    #   例: 番号 12345671 -> 口座番号 1234567
    #   例: 番号 123451   -> 口座番号 0012345
    #
    # 注意:
    # - 記号が 0 から始まる振替口座は、このConverterでは扱わない。
    # - 公式ページでは、振替口座など別パターンも案内されている。
    # - 本Converterの対象外パターンは validation で弾き、必要になったら別途拡張する。
    # - 振込先口座番号・カナ氏名を間違えると別人の口座に振り込まれる可能性があるため、
    #   UI側でも変換後の店番・口座番号を表示して確認できるようにする。
    Result = Struct.new(
      :bank_code,
      :branch_code,
      :account_type,
      :account_number,
      keyword_init: true
    )

    class Error < StandardError; end

    JP_BANK_CODE = "9900"

    def initialize(symbol:, number:)
      @symbol = symbol.to_s.delete("-").strip
      @number = number.to_s.delete("-").strip
    end

    def call
      validate!

      Result.new(
        bank_code: JP_BANK_CODE,
        branch_code: branch_code,
        account_type: :ordinary,
        account_number: account_number
      )
    end

    private

    attr_reader :symbol, :number

    def validate!
      # Phase1では、ゆうちょの総合口座・通常貯金・通常貯蓄貯金のみ対応する。
      # そのため、記号は「1」始まりの5桁に限定する。
      raise Error, "記号は5桁で入力してください" unless symbol.match?(/\A1\d{4}\z/)

      # 通帳等では番号が最大8桁で表示される。
      # 振込用口座番号は末尾1桁を除いて作るため、最低2桁は必要。
      raise Error, "番号は2〜8桁で入力してください" unless number.match?(/\A\d{2,8}\z/)
    end

    def branch_code
      "#{symbol[1, 2]}8"
    end

    def account_number
      number_without_check_digit = number[0...-1]
      number_without_check_digit.rjust(7, "0")
    end
  end
end
