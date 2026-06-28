# Payment Statement PDF

## 1. 目的

この文書は、支払済み精算に対する以下のPDF帳票の生成方式を定める。

- 店舗管理者向け: 支払明細書PDF
- system_admin向け: 支払明細書（運営控え）PDF

この文書は #933 の成果物であり、#934「支払済み精算の支払明細書PDF・運営控えPDFを追加する」の実装前提を固める。

#934 では、この方針に沿って Prawn（RubyでPDFを直接生成するライブラリ）によるPDF生成Service、Controller / route、画面導線、Docker / CI / production の日本語フォント依存を追加する。フォントファイル自体はリポジトリに含めない。

---

## 2. 現状確認

現状把握では実コードを正として扱う。

確認した主な実コード・設定:

- `Gemfile`
- `Gemfile.lock`
- `Dockerfile`
- `Dockerfile.production`
- `.github/workflows/ci.yml`
- `app/controllers/admin/settlements_controller.rb`
- `app/controllers/system_admin/settlements_controller.rb`
- `app/models/settlement.rb`
- `docs/design/settlement_lifecycle.md`

現状:

- #934 で `Gemfile` / `Gemfile.lock` に Prawn（RubyでPDFを直接生成するライブラリ）を追加し、test環境にはPDFテキスト抽出用の `pdf-reader` を追加する。Grover（ChromiumでHTMLをPDF化する方式）、WickedPDF（wkhtmltopdfでHTMLをPDF化する方式）、PDFKit（wkhtmltopdf系）は追加しない。
- #934 で支払明細書PDFのController / route / Service / view導線を追加する。
- Docker（コンテナ実行環境）と production Dockerfile には、PDF生成に必要な日本語フォントとして `fonts-noto-cjk` と `fonts-ipaexfont` を追加する。Chromium、wkhtmltopdfは追加しない。
- CI（自動テスト環境）には、PDF生成テスト用の日本語フォントとして `fonts-noto-cjk` と `fonts-ipaexfont` を追加する。Chromium、wkhtmltopdfは追加しない。
- `Settlement` は `paid_at` と `paid_by_user` を持ち、`paid?` の場合は `paid_at` が必須である。
- `Settlement` の金額・期間は confirmed 以降変更不可であり、振込先スナップショットは exported 以降変更不可である。
- 精算ライフサイクル上、正式な支払明細書PDFの対象は `paid` の `Settlement` のみである。

---

## 3. 対象帳票

### 3.1 店舗管理者向け

名称:

- 支払明細書

用途:

- 店舗管理者が、自店舗の支払済み精算について、支払内容を確認・保存するためのPDF。

### 3.2 system_admin向け

名称:

- 支払明細書（運営控え）

用途:

- 運営側が、同じ支払済み精算について、監査・問い合わせ対応・社内保管用に確認するためのPDF。

### 3.3 共通方針

- 店舗向けと運営控えは、同じPDF生成Service（業務処理を集約するクラス）を使う。
- 帳票タイトル、備考文言、必要ならフッター表記だけを出力種別で切り替える。
- 金額、対象期間、店舗名、支払日、振込先スナップショットは同一の正本データを参照する。

---

## 4. 発行対象

正式なPDF発行対象:

- `Settlement.paid` のみ

正式PDF対象外:

- `draft`
- `confirmed`
- `exported`

理由:

- `exported` はCSV生成済みであり、銀行振込成功を意味しない。
- `paid` が正式な支払済み状態であり、支払明細書PDFは精算ライフサイクルの出口として扱う。
- PDFの支払日は `Settlement.paid_at` を正本として使う。

guard（防御条件）:

- Controller（リクエストを受ける層）で `paid` のみ取得する。
- Service側でも `settlement.paid?` を確認し、誤用時は例外または明示的な失敗を返す。

---

## 5. 表示予定項目

最低限、以下を表示する。

| 項目 | 参照元 | 備考 |
| --- | --- | --- |
| 支払明細番号 | `Settlement.id` ベース | 例: `PS-00000001`。法的な連番要件が必要なら別Issueで採番設計する |
| 発行日 | PDF生成日 | JST基準 |
| 支払日 | `settlements.paid_at` | `paid` の正本 |
| 対象期間 | `period_from` / `period_to` | JST表示。終了は精算期間の排他的終端である点に注意 |
| 店舗名 | `settlement.store.name` | 店舗向け・運営控え共通 |
| 精算ステータス | `paid` | 表示文言は「支払済み」 |
| 売上総額 | `gross_yen` | 円表示 |
| 運営手数料 | `platform_fee_yen` | 円表示 |
| 店舗支払額 | `store_share_yen` | 円表示。振込額として扱う |
| 振込先口座 | `Settlement` の振込先スナップショット | 現在の `StorePayoutAccount` は参照しない |
| 備考文言 | 固定文言 | 例: 「本明細は支払済み精算に基づいて発行しています」 |

振込先口座の表示方針:

- `payout_bank_code`
- `payout_branch_code`
- `payout_account_type`
- `payout_account_number`
- `payout_account_holder_kana`

口座番号はマスク表示とする。

例:

```text
銀行コード: 0038
支店コード: 101
口座種別: 普通
口座番号: ***4567
口座名義: ﾃｽﾄ
```

口座番号以外のマスク要否は #934 実装時に最終確認する。ただし、PDFには `Settlement` に保存済みの exported 時点スナップショットを使う。

---

## 6. 比較した生成方式

### 6.1 Prawn（RubyでPDFを直接生成するライブラリ）

概要:

- RubyコードでPDFを直接組み立てる方式。
- HTMLやブラウザレンダリングには依存しない。
- Prawn公式READMEでは pure Ruby のPDF生成ライブラリとして説明され、埋め込みTrueTypeフォント、UTF-8ベースのフォント、fallback font（不足字形の代替フォント）などに対応している。

評価:

| 観点 | 評価 |
| --- | --- |
| 日本語PDF | TTF / OTF の日本語フォントを明示指定すれば安定しやすい |
| Docker | Chromiumやwkhtmltopdf不要。日本語フォントの準備が主な追加依存 |
| CI | Ruby gem + 日本語フォントで完結しやすい |
| production | headless browserなしで軽い |
| フォント | 明示的なフォントパス設定が必要 |
| 固定帳票 | 向いている。座標・罫線・固定項目をコードで制御できる |
| 保守性 | 帳票項目が少ない場合は高い。複雑なHTML再現には向かない |
| テスト | Service単体でPDFバイナリ生成を検証しやすい |
| 既存Rails構成 | Service層に閉じやすく、Controllerを薄く保てる |

懸念:

- HTML/CSSの知識をそのまま使えない。
- 日本語フォントが存在しない環境では日本語が出ない、または生成に失敗する。
- 細かいレイアウトはRubyコードで管理する必要がある。

### 6.2 Grover（ChromiumでHTMLをPDF化する方式）

概要:

- Rails viewなどからHTMLを作り、Google Puppeteer / ChromiumでPDF化する方式。
- 既存のHTML/CSS資産を活用しやすい。

評価:

| 観点 | 評価 |
| --- | --- |
| 日本語PDF | ブラウザが使えるフォントを解決できれば表示しやすい |
| Docker | Chromium / Puppeteer / Node周辺依存が重い |
| CI | browser依存をCIへ追加する必要がある |
| production | コンテナサイズ・起動・sandbox設定などの運用負荷が増える |
| フォント | WebフォントまたはOSフォントの管理が必要 |
| 固定帳票 | 可能だが、今回のような小さな固定帳票には過剰 |
| 保守性 | HTML帳票が必要な場合は高いが、印刷CSSの差分管理が必要 |
| テスト | ブラウザ依存で遅くなりやすい |
| 既存Rails構成 | viewを流用できるが、今回はWeb画面そのものをPDF化しない |

不採用理由:

- 今回はWeb画面をPDF化する目的ではなく、1〜数ページの固定帳票である。
- Chromium / Puppeteer 依存はDocker、CI、productionの追加負荷が大きい。
- レイアウトの派手さより、安定性・正確性・保守性を優先する今回の帳票には過剰である。

### 6.3 WickedPDF（wkhtmltopdfでHTMLをPDF化する方式）

概要:

- HTMLをwkhtmltopdf外部コマンドでPDF化するRails向けgem。
- WickedPDF公式READMEでも、wkhtmltopdfのshell utility（外部コマンド）を使う方式として説明されている。

評価:

| 観点 | 評価 |
| --- | --- |
| 日本語PDF | OSフォントとwkhtmltopdf側の描画に依存する |
| Docker | wkhtmltopdfバイナリの導入が必要 |
| CI | wkhtmltopdf導入が必要 |
| production | バイナリ互換性・依存関係の管理が重い |
| フォント | OSフォントとwkhtmltopdfのレンダリング差分に注意が必要 |
| 固定帳票 | 可能だがHTML印刷再現に寄る |
| 保守性 | wkhtmltopdf固有の制約を抱える |
| テスト | 外部コマンド依存で遅く、不安定化しやすい |
| 既存Rails構成 | Rails viewとは相性があるが、今回の帳票には過剰 |

不採用理由:

- wkhtmltopdf本体はGitHub上で archived（読み取り専用）になっている。
- Ruby / Rails / OSの更新に対して外部バイナリ依存が重い。
- 今回は固定帳票であり、HTML再現性よりPDF生成の安定性を優先する。

### 6.4 その他方式

#### PDFKit（wkhtmltopdf系）

- wkhtmltopdfに依存するHTML to PDF方式。
- WickedPDFと同じく、外部バイナリ依存が重い。
- 今回は不採用。

#### HexaPDF / CombinePDF

- RubyでPDFを扱えるライブラリ。
- 既存PDFの編集・結合・低レベル操作には候補になる。
- 今回は「帳票を新規生成する」用途であり、Prawnの方が実装しやすい。

---

## 7. 採用方式

採用方式:

- Prawn（RubyでPDFを直接生成するライブラリ）

採用理由:

- 支払明細書は1〜数ページの固定帳票であり、HTML再現より固定レイアウトの安定性が重要である。
- Chromiumやwkhtmltopdfなどの外部レンダリングエンジンをproduction / CIに追加しなくてよい。
- Ruby Service内でPDFバイナリを直接返せるため、既存の「金銭処理・状態変更はServiceに寄せる」設計と相性がよい。
- Controllerは認可、`paid` guard、Service呼び出し、`send_data` に留められる。
- PDF内容の一部検証やPDFバイナリ生成の単体テストがしやすい。
- 日本語フォントを明示指定すれば、環境差分を管理しやすい。

不採用ではないが注意する点:

- Prawn単体ではHTML/CSSレイアウトを使わないため、帳票レイアウトはRubyコードで実装する。
- 日本語フォントの準備とライセンス確認は #934 の実装前に必ず行う。
- 表が複雑になる場合は `prawn-table` を検討できるが、まずはPrawn本体の `text_box`、罫線、bounding box（描画領域）で十分か確認する。

---

## 8. 日本語フォント方針

### 8.1 Prawnで日本語表示する場合

Prawnで日本語を表示するには、PDF組み込みフォントではなく、日本語グリフ（字形）を含むTTF / OTFフォントを明示的に登録する必要がある。

方針:

- #934では、PDF生成Service起動時に日本語フォントパスを解決する。
- フォントが見つからない場合は、文字化けPDFを生成せず、明示的に失敗させる。
- PDFには使用フォントを埋め込み、表示環境に依存しないようにする。

### 8.2 フォントファイルをリポジトリに含めるか

現時点の方針:

- このIssueではフォントファイルを追加しない。
- #934でも、まずはOS / Docker image側にインストールした日本語フォントを使う方針を第一候補とする。
- ライセンス不明のフォント、OSにたまたま入っているだけの商用フォント、配布条件が確認できないフォントはリポジトリに入れない。

理由:

- 日本語フォントはファイルサイズが大きく、リポジトリ肥大化につながる。
- ライセンス確認なしでフォントを同梱すると、配布条件上のリスクがある。
- Docker / CI / productionで同じパッケージを入れる方が、まずは運用管理しやすい。

将来、OSパッケージの差分が問題になる場合:

- ライセンス確認済みのフォントのみを `vendor/fonts/` などに同梱する案を別途検討する。
- 同梱する場合は、フォント本体、ライセンスファイル、出典、バージョンをセットで管理する。

### 8.3 OS / Docker image側のフォント候補

#934で確認する候補:

- Noto Sans CJK JP / Noto Sans JP
- IPAex Gothic
- Source Han Sans JP

第一候補:

- Noto Sans CJK JP または Noto Sans JP

理由:

- 日本語を含むCJK（中国語・日本語・韓国語）文字を広くカバーする。
- Noto公式ドキュメントではOpen Font License（OFL）で利用できると説明されている。
- Debian / Ubuntu系では `fonts-noto-cjk` などのパッケージで入れられる可能性が高い。

#934で確認すること:

- 開発Docker、production Docker、CIで同じフォントパッケージを入れられるか。
- 実際のフォントファイルパス。
- Prawnがそのファイルを読み込めるか。
- PDF出力後に日本語、半角カナ、円記号、長音、括弧、口座名義が表示されるか。
- ライセンス表記をdocsまたは依存管理上どこに残すか。

### 8.4 推奨する実装時設定案

#934で確認した標準候補:

```ruby
PAYMENT_STATEMENT_PDF_FONT_PATH=/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf
PAYMENT_STATEMENT_PDF_FONT_BOLD_PATH=/usr/share/fonts/opentype/ipaexfont-gothic/ipaexg.ttf
```

Docker / CI / production には `fonts-noto-cjk` と `fonts-ipaexfont` を追加する。Debian / Ubuntu系の `fonts-noto-cjk` は `.ttc` 形式になるため、Prawnの標準候補ではTTF / OTFを優先し、`fonts-ipaexfont` の `ipaexg.ttf` をfallbackとして使う。Noto系のTTF / OTFフォントを別途用意する場合は、上記の環境変数で明示する。

Service側では以下の順で解決する案とする。

1. `ENV["PAYMENT_STATEMENT_PDF_FONT_PATH"]`
2. Docker / CIで決めた標準パス
3. 見つからなければ明示的にエラー

---

## 9. #934 実装方針案

### 9.1 Gem候補

production / development共通:

```ruby
gem "prawn"
```

必要になった場合のみ検討:

```ruby
gem "prawn-table"
```

test環境でPDF内テキスト抽出をするための追加gem:

```ruby
group :test do
  gem "pdf-reader"
end
```

#934では、PDF本文の主要項目を検証するため test 環境に `pdf-reader` を追加する。`prawn-table` は初期実装では追加しない。

### 9.2 Service構成案

候補:

```text
app/services/settlements/payment_statement_pdf_service.rb
```

呼び出し案:

```ruby
Settlements::PaymentStatementPdfService.new(
  settlement: settlement,
  copy: false,
  issued_at: Time.zone.now
).call
```

戻り値案:

```ruby
{
  filename: "payment_statement_PS-00000001.pdf",
  content_type: "application/pdf",
  data: pdf_binary
}
```

または、Serviceをシンプルにする場合:

```ruby
pdf_binary = Settlements::PaymentStatementPdfService.new(
  settlement: settlement,
  copy: false
).call
```

Service責務:

- `paid?` guard
- PDF用の表示値整形
- 金額、期間、支払日、振込先マスクの組み立て
- Prawn文書生成
- 日本語フォント設定

Controller責務:

- 認証・認可
- 対象 `Settlement` の取得
- `paid` の対象に絞る
- Service呼び出し
- `send_data` でPDFレスポンスを返す

### 9.3 route / Controller案

店舗管理者側:

```text
GET /admin/settlements/:id/payment_statement
```

route案:

```ruby
namespace :admin do
  resources :settlements, only: %i[index show] do
    member do
      get :payment_statement
    end
  end
end
```

取得方針:

```ruby
settlement = current_store.settlements.paid.find(params[:id])
```

system_admin側:

```text
GET /system_admin/settlements/:id/payment_statement
```

route案:

```ruby
namespace :system_admin do
  resources :settlements, only: %i[index show] do
    member do
      get :payment_statement
    end
  end
end
```

取得方針:

```ruby
settlement = Settlement.paid.includes(:store).find(params[:id])
```

system_admin向けは `copy: true` とし、タイトルを「支払明細書（運営控え）」にする。

### 9.4 レスポンス方針

- `Content-Type`: `application/pdf`
- `Content-Disposition`: `attachment`
- ファイル名:
  - 店舗向け: `payment_statement_PS-00000001.pdf`
  - 運営控え: `payment_statement_PS-00000001_admin_copy.pdf`

ファイル名には店舗名を含めない。

理由:

- 日本語・記号・スペースを含むファイル名のブラウザ差分を避ける。
- IDベースで問い合わせ対応しやすくする。

### 9.5 guard方針

店舗管理者:

- 自店舗の `paid` 精算だけ取得できる。
- 他店舗の精算は `ActiveRecord::RecordNotFound` または404相当にする。
- `draft` / `confirmed` / `exported` は取得できない。

system_admin:

- 全店舗の `paid` 精算を取得できる。
- `draft` / `confirmed` / `exported` は取得できない。

Service:

- `paid?` でない場合は `ArgumentError` などで失敗させる。
- Controllerでの絞り込み漏れを防ぐ二重guardとする。

---

## 10. レイアウト方針

初期実装ではA4縦、1ページを基本とする。

構成案:

1. タイトル
2. 明細番号・発行日
3. 店舗名・対象期間・支払日
4. 金額サマリー
5. 振込先口座
6. 備考
7. フッター

金額サマリー:

| 表示名 | 値 |
| --- | --- |
| 売上総額 | `gross_yen` |
| 運営手数料 | `platform_fee_yen` |
| 店舗支払額 | `store_share_yen` |

注意:

- 見た目の完全一致より、読みやすさ、金額の正確性、文字化けしないことを優先する。
- 帳票項目が増える場合でも、まずはService内の小さなprivate methodに分ける程度に留め、過度な抽象化はしない。
- PDFテンプレート用DSLやHTMLテンプレートは今回の初期方針では使わない。

---

## 11. テスト方針

#934で最低限確認すること:

- `paid` の `Settlement` だけPDF生成できる。
- `draft` / `confirmed` / `exported` は拒否される。
- 店舗管理者は自店舗の `paid` 精算のみ取得できる。
- 店舗管理者は他店舗の精算を取得できない。
- system_admin は全店舗の `paid` 精算を取得できる。
- PDFレスポンスの `Content-Type` が `application/pdf` である。
- `Content-Disposition` のファイル名が妥当である。
- PDF生成ServiceがPDFバイナリを返す。
- PDFバイナリが `%PDF` で始まる。
- 金額、対象期間、店舗名、支払日、振込先マスクが反映されることを可能な範囲で検証する。
- `Settlement` 側の振込先スナップショットを参照し、現在の `StorePayoutAccount` を参照しない。
- 日本語、半角カナ、円表示が文字化けしないことを開発環境で確認する。

見た目の完全一致テストは必須にしない。

理由:

- PDFバイナリは生成日時、内部オブジェクト順、フォント埋め込みなどで差分が出やすい。
- 初期実装では固定文言・主要値・レスポンス形式・権限をテストし、視覚的な完全一致は手動確認または必要時の画像比較に留める。

テスト種別:

- Service test
- admin integration test
- system_admin integration test

必要になった場合:

- `pdf-reader` でテキスト抽出し、主要文言と金額を検証する。
- PDFレンダリング画像比較は、レイアウト崩れが問題になった場合のみ追加する。

---

## 12. #934で実装しない方がよいこと

初期実装では以下を広げない。

- 支払明細番号用の新規テーブルや連番採番
- PDFファイルの永続保存
- 再発行履歴
- 電子帳簿保存法など法令対応の断定
- paid後の取消・再精算
- メール添付
- 銀行API振込結果との自動連動

これらが必要になった場合は、別Issueで扱う。

---

## 13. 結論

支払明細書PDF生成方式は、Prawn（RubyでPDFを直接生成するライブラリ）を採用する。

Grover（ChromiumでHTMLをPDF化する方式）とWickedPDF（wkhtmltopdfでHTMLをPDF化する方式）は、HTML再現性が必要な帳票では候補になるが、今回の支払明細書は1〜数ページの固定帳票であるため不採用とする。

#934では、Prawn + 明示的な日本語フォント設定 + Service中心の構成で実装する。日本語フォントは、まずOS / Docker image側にインストールしたライセンス確認済みフォントを使う方針とし、フォントファイルのリポジトリ同梱は行わない。

---

## 14. 参考情報

- Prawn: https://github.com/prawnpdf/prawn
- Grover: https://github.com/Studiosity/grover
- WickedPDF: https://github.com/mileszs/wicked_pdf
- wkhtmltopdf: https://github.com/wkhtmltopdf/wkhtmltopdf
- Noto fonts: https://notofonts.github.io/noto-docs/website/use/
- Noto CJK fonts: https://github.com/notofonts/noto-cjk
- Source Han Sans license: https://github.com/adobe-fonts/source-han-sans/blob/master/LICENSE.txt
