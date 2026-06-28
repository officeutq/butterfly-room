# frozen_string_literal: true

require "prawn"

module Settlements
  class PaymentStatementPdfService
    CONTENT_TYPE = "application/pdf"
    FONT_FAMILY = "PaymentStatementJapanese"
    FONT_PATH_ENV = "PAYMENT_STATEMENT_PDF_FONT_PATH"
    FONT_BOLD_PATH_ENV = "PAYMENT_STATEMENT_PDF_FONT_BOLD_PATH"
    ZONE = "Asia/Tokyo"

    FONT_CANDIDATE_PATHS = [
      "/usr/share/fonts/truetype/noto/NotoSansJP-Regular.ttf",
      "/usr/share/fonts/opentype/noto/NotoSansCJKjp-Regular.otf",
      "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.otf",
      "/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf",
      "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"
    ].freeze

    BOLD_FONT_CANDIDATE_PATHS = [
      "/usr/share/fonts/truetype/noto/NotoSansJP-Bold.ttf",
      "/usr/share/fonts/opentype/noto/NotoSansCJKjp-Bold.otf",
      "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.otf",
      "/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf",
      "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"
    ].freeze

    class MissingFontError < StandardError; end

    def initialize(settlement:, copy: false, issued_at: Time.zone.now)
      @settlement = settlement
      @copy = copy
      @issued_at = issued_at
    end

    def call
      raise ArgumentError, "支払済みの精算のみ支払明細書PDFを発行できます" unless @settlement.paid?

      {
        filename: filename,
        content_type: CONTENT_TYPE,
        data: build_pdf
      }
    end

    private

    def build_pdf
      font_path = resolve_font_path!
      bold_font_path = resolve_bold_font_path || font_path

      pdf = Prawn::Document.new(
        page_size: "A4",
        margin: 48,
        compress: false,
        info: { Title: title }
      )

      pdf.font_families.update(
        FONT_FAMILY => {
          normal: font_path,
          bold: bold_font_path
        }
      )
      pdf.font(FONT_FAMILY)

      draw_header(pdf)
      draw_settlement_summary(pdf)
      draw_amounts(pdf)
      draw_payout_snapshot(pdf)
      draw_note(pdf)
      draw_footer(pdf)

      pdf.render
    end

    def draw_header(pdf)
      pdf.text title, size: 22, style: :bold, align: :center
      pdf.move_down 20
      draw_rows(
        pdf,
        [
          [ "支払明細番号", statement_number ],
          [ "発行日", format_date(@issued_at) ]
        ]
      )
    end

    def draw_settlement_summary(pdf)
      section_title(pdf, "精算情報")
      rows = [
        [ "店舗名", @settlement.store.name ],
        [ "対象期間", "#{format_datetime(@settlement.period_from)} 〜 #{format_datetime(@settlement.period_to)}（終了日時は含みません）" ],
        [ "支払日", format_datetime(@settlement.paid_at) ],
        [ "精算ステータス", "支払済み" ]
      ]
      rows << [ "帳票区分", "運営控え" ] if @copy

      draw_rows(pdf, rows)
    end

    def draw_amounts(pdf)
      section_title(pdf, "支払金額")
      draw_rows(
        pdf,
        [
          [ "売上総額", format_money(@settlement.gross_yen) ],
          [ "運営手数料", format_money(@settlement.platform_fee_yen) ],
          [ "店舗支払額", format_money(@settlement.store_share_yen) ]
        ]
      )
    end

    def draw_payout_snapshot(pdf)
      section_title(pdf, "振込先口座")
      draw_rows(
        pdf,
        [
          [ "金融機関コード", present_or_dash(@settlement.payout_bank_code) ],
          [ "支店コード", present_or_dash(@settlement.payout_branch_code) ],
          [ "口座種別", payout_account_type_label ],
          [ "口座番号（マスク）", masked_account_number ],
          [ "口座名義", present_or_dash(@settlement.payout_account_holder_kana) ]
        ]
      )
    end

    def draw_note(pdf)
      section_title(pdf, "備考")
      note_lines.each do |line|
        pdf.text(line, size: 10, leading: 4)
        pdf.move_down 4
      end
    end

    def draw_footer(pdf)
      pdf.number_pages(
        "<page> / <total>",
        at: [ pdf.bounds.left, 0 ],
        align: :right,
        size: 8
      )
    end

    def section_title(pdf, text)
      pdf.move_down 8
      pdf.fill_color "222222"
      pdf.text text, size: 13, style: :bold
      pdf.stroke_color "999999"
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.fill_color "000000"
    end

    def draw_rows(pdf, rows)
      rows.each do |label, value|
        pdf.formatted_text(
          [
            { text: "#{label}: ", styles: [ :bold ] },
            { text: value.to_s }
          ],
          size: 10,
          leading: 3
        )
        pdf.stroke_color "DDDDDD"
        pdf.stroke_horizontal_rule
        pdf.move_down 6
      end
      pdf.move_down 6
    end

    def resolve_font_path!
      if ENV[FONT_PATH_ENV].present?
        path = ENV.fetch(FONT_PATH_ENV)
        return path if File.file?(path)

        raise MissingFontError, "#{FONT_PATH_ENV} に指定された日本語フォントが見つかりません: #{path}"
      end

      FONT_CANDIDATE_PATHS.find { |path| File.file?(path) } ||
        raise(
          MissingFontError,
          "支払明細書PDF用の日本語フォントが見つかりません。#{FONT_PATH_ENV} を設定するか、Docker/CI/productionに日本語TTF/OTFフォントを追加してください。"
        )
    end

    def resolve_bold_font_path
      if ENV[FONT_BOLD_PATH_ENV].present?
        path = ENV.fetch(FONT_BOLD_PATH_ENV)
        return path if File.file?(path)

        raise MissingFontError, "#{FONT_BOLD_PATH_ENV} に指定された日本語フォントが見つかりません: #{path}"
      end

      BOLD_FONT_CANDIDATE_PATHS.find { |path| File.file?(path) }
    end

    def title
      @copy ? "支払明細書（運営控え）" : "支払明細書"
    end

    def note_lines
      if @copy
        [
          "本書は支払済みの精算に基づいて発行しています。",
          "振込先はCSV出力時点で精算に保存された口座情報を使用しています。",
          "支払済み以外の精算は、正式な支払明細書PDFの発行対象外です。"
        ]
      else
        [
          "本書は支払済みの精算に基づいて発行しています。",
          "振込先は、支払処理時点で登録されていた口座情報を表示しています。"
        ]
      end
    end

    def statement_number
      format("PS-%08d", @settlement.id)
    end

    def filename
      suffix = @copy ? "_admin_copy" : ""
      "payment_statement_#{statement_number}#{suffix}.pdf"
    end

    def format_money(value)
      "#{number_with_delimiter(value.to_i)}円"
    end

    def number_with_delimiter(value)
      sign = value.negative? ? "-" : ""
      digits = value.abs.to_s
      "#{sign}#{digits.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end

    def format_date(value)
      time = value.in_time_zone(ZONE)
      "#{time.year}年#{time.month}月#{time.day}日"
    end

    def format_datetime(value)
      time = value.in_time_zone(ZONE)
      "#{time.year}年#{time.month}月#{time.day}日 #{time.strftime('%H:%M')}"
    end

    def payout_account_type_label
      case @settlement.payout_account_type.to_s
      when "ordinary"
        "普通"
      when "current"
        "当座"
      else
        present_or_dash(@settlement.payout_account_type)
      end
    end

    def masked_account_number
      value = @settlement.payout_account_number.to_s
      return "-" if value.blank?

      visible = value.last(4)
      "#{"*" * [ value.length - visible.length, 0 ].max}#{visible}"
    end

    def present_or_dash(value)
      value.presence || "-"
    end
  end
end
