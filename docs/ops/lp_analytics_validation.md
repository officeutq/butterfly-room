# LP行動分析 横断検証・rollout手順

`stores/lp_202609`の公開判定、広告切替、rollback、公開後比較については、[202609版公開準備チェックリスト](store_lp_202609_release.md)もあわせて確認する。

## 1. 目的と安全境界

`stores/lp_202607`と`stores/lp_202609`のLP表示から店舗登録・お問い合わせ完了、system_admin分析、Googleスプレッドシート日次出力までを横断確認する。分析の正本はRails DBであり、Googleスプレッドシートは匿名の日次集計の共有先である。

2026年8月9日の#1033検証はstagingだけで実施した。production containerの再起動・再作成、production Spreadsheetへの書込み、production Secret値の取得、自動出力の起動は行っていない。

秘密値、Spreadsheet ID、Secret ID・ARN、サービスアカウントメール、公開訪問ID、フォーム入力値をIssue・PR・通常logへ記録しない。

## 2. 確定した判定基準

- 訪問は匿名の公開訪問IDで関連付ける
- 同じLP・UTM・referral codeで最後の操作から30分以内は同じ訪問を継続する
- 30分超過、UTM変更、referral code変更、有効な訪問IDなしは新しい訪問とする
- 同じ公開訪問IDがあってもLP識別子を切り替えた場合は新しい訪問とする
- reloadは同じ訪問の`lp_view`を追加する
- browserが同じ公開訪問IDを引き継いだ複数tabは同じ訪問とする
- LPを経由しない通常の登録・お問い合わせフォーム流入は分析対象にしない
- 日次・管理画面の期間はAsia/Tokyoの訪問開始日時で判定する
- 前日に開始して翌日に完了した場合、完了は訪問開始日の実績へ含める
- 自動日次Jobは前日を終端とする直近7日を古い順に再集計し、遅延完了を取り込む
- CTAクリック訪問数は匿名訪問で重複排除し、総クリック回数は保存されたクリックevent数とする
- 週間CV率は日別CV率の単純平均ではなく、週間完了訪問数合計 ÷ 週間LP訪問数合計で求める

## 3. 2026年8月9日 staging検証結果

### 基盤と安全設定

| 項目 | 結果 |
| --- | --- |
| migration | LP訪問・完了関連・Sheets出力の3 migrationが`up` |
| app / worker | 最新imageで再作成後に両containerが稼働 |
| health check | `Host: staging.butterflyve.jp`付きloopback `/up`が200 |
| 定期task | `LpAnalytics::Sheets::ExportRecentDaysJob`、`20 2 * * * Asia/Tokyo`、default queueを確認 |
| staging自動出力 | `LP_ANALYTICS_SHEETS_EXPORT_ENABLED=false`を維持し、enqueueしても「disabled」でskip、出力状態に変化なし |
| Secret / Sheets | staging workerからstaging専用`daily_raw`をreadできることを確認 |
| production | 操作なし |

### 店舗登録・お問い合わせ

専用の`utm_campaign`とシナリオ別`utm_content`を使い、private window（プライベートウィンドウ）から操作した。

| シナリオ | 訪問 | CTAクリック訪問 | 総クリック | フォーム到達訪問 | 完了件数 | 完了訪問 | CV率 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 店舗登録 | 3 | 2 | 4 | 2 | 1 | 1 | 0.33333333 |
| お問い合わせ | 2 | 2 | 2 | 1 | 1 | 1 | 0.5 |

- スクロール25%・50%・75%・90%、主要セクション、FAQ、複数CTAを操作した
- Rails DB、system_adminのKPI・ファネル・CTA分析・匿名訪問詳細、業務完了レコードを突合した
- 店舗登録完了とお問い合わせ完了が、それぞれLPから引き継いだ同じ匿名訪問へ関連付くことを確認した
- validation errorでは完了eventを作らず、正常保存時だけ完了件数へ反映する既存integration testも通過した

### 訪問切替

| 条件 | 結果 |
| --- | --- |
| 同じ流入でreload | 同一訪問。`lp_view`だけ増加 |
| 30分以内・同じ公開訪問IDの複数tab | 同一訪問 |
| UTM変更 | 新規訪問 |
| referral code変更 | 新規訪問 |
| 31分経過相当にした後の再表示 | 新規訪問 |
| LPを経由しない通常フォーム表示 | 訪問数・フォーム表示event数とも変化なし |

Chrome系browserでは、private windowを複数開いてもcookieやログイン状態を共有する。完全に新しいbrowser状態が必要なときは、開いているprivate windowをすべて閉じてから開き直す。store_adminとしてログイン済みの状態で「お問い合わせはこちら」を押すと、既存の認証導線によりダッシュボードへ遷移する場合がある。

LP検証URLには空白を入れない。次は構造だけを示すダミーであり、`<VALID_STAGING_REFERRAL_CODE>`はstagingで有効な値へ置き換える。

```text
https://staging.butterflyve.jp/stores/lp_202607?from=staging_validation&utm_source=manual&utm_medium=validation&utm_campaign=<CAMPAIGN>&utm_content=<SCENARIO>&ref=<VALID_STAGING_REFERRAL_CODE>
```

### 日次集計とGoogleスプレッドシート

- Rails日次集計のシナリオ別数値がsystem_admin表示と一致した
- staging専用`daily_raw`のheaderがRails管理headerと一致した
- 初回手動出力後、同じ日を再出力しても行数とaggregation keyが増えなかった
- 訪問切替シナリオ追加後の再出力では、対象日4行・LP訪問合計9、aggregation key重複なしを確認した
- `lp_analytics_sheet_exports`は`succeeded`、最終`attempt_count=3`、`row_count=4`、`needs_retry=false`
- 自動出力は検証後も`false`のままで、worker再起動後にも予期しない試行回数増加がないことを確認した

#1043の端末・セクション列追加後は、上記に加えて`device_type`別の訪問数・完了訪問数・CV率と、8つの主要セクションの到達訪問数・到達率をRails DBと照合する。旧headerからの移行では対象期間を全件再出力し、端末軸を含まない旧aggregation keyが残っていないことを確認する。実Spreadsheetの移行はPR・自動testでは行わず、[Google Sheets連携運用手順](lp_analytics_google_sheets.md)の承認手順に従う。

#1067の202609版追加後は、LP識別子、`device_type`、`utm_content`を分け、202607版と202609版それぞれの8セクション、CTA、フォーム表示、完了を照合する。202609版LP上のFAQはリンクCTAまでを対象とし、FAQページ内の質問展開はFAQページの計測として確認する。42列headerから58列headerへの実Spreadsheet移行はPR・自動testでは行わず、同じ運用手順の承認境界に従う。

### 個人情報・秘密情報

| 対象 | 結果 |
| --- | --- |
| 分析DB schema | 氏名、メール、電話、password、本文、IP、raw User-Agent、cookie列なし |
| event metadata | 許可keyは`viewport_type`のみ。whitelist違反0 |
| 流入値 | 上限超過0 |
| DB / Sheets値 | メール形式・private key・token・cookie値に一致する値0 |
| Rails log | フォーム親parameterを`[FILTERED]`化。検証用入力値と認証materialの露出0 |
| 業務データ | log確認用422 requestの前後で店舗・お問い合わせ件数に変化なし |

フォームpayload全体のlog filterは#1041で追加し、stagingへ反映後に実requestで確認した。

## 4. 自動テストで確認する項目

実Google APIへ意図的な障害を発生させず、通常testではmockを使う。

| 分類 | 確認内容 |
| --- | --- |
| 日付 | 23:59台開始、翌日00:00台完了、訪問開始日への帰属、今日・7日・30日・任意期間、02:20 JSTの直近7日 |
| event | browser event IDの再送、訪問内到達eventの重複、CTA・FAQ複数回、LP別keyの混在拒否、許可外値・metadata拒否 |
| browser | API失敗を画面へ伝播しない、Turbo preview / prerender除外、CSRF、匿名payload限定 |
| Sheets | 初回・同日更新・消滅行、duplicate key、header不一致、部分行、429・5xx・timeout retry、401・403非retry |
| 業務分離 | Sheets失敗時にDB transactionを保持しない、登録・お問い合わせ完了を業務保存成功後に記録 |
| 回帰 | GTM表示と完了event、UTM・referral code引継ぎ、登録・お問い合わせ、system_admin認可、Solid Queue recurring設定、精算画面・処理 |
| 性能 | 分析対象を50訪問増やしてもSELECT query数が増えないこと、日次SQLの訪問単位CTE、最近の完了20件ページング（最大100件）、Sheets batch update |

主な確認コマンド:

```bash
docker compose exec -T app bin/rails test \
  test/models/lp_analytics \
  test/services/lp_analytics \
  test/queries/lp_analytics \
  test/jobs/lp_analytics \
  test/lib/tasks/lp_analytics_sheets_export_task_test.rb \
  test/config/lp_analytics_recurring_test.rb \
  test/integration/lp_analytics_events_test.rb \
  test/integration/lp_analytics_completions_test.rb \
  test/integration/lp_analytics_browser_tracking_test.rb \
  test/integration/system_admin_lp_analytics_test.rb

npm run test:js
npm run build:css
```

## 5. staging再検証手順

1. `git status --short`で既存の未追跡ファイルを確認し、削除・移動しない。
2. `df -h /`と`docker system df`でbuild前の空き容量を確認する。
3. appを起動し、staging Host header付き`/up`が200になってからworkerを起動する。
4. migration、recurring task、staging自動出力`false`を確認する。
5. private windowをすべて閉じてから新しく開き、空白のないUTM・referral code付きURLでシナリオを開始する。
6. system_adminで同じ条件を指定し、匿名訪問詳細と業務完了を確認する。
7. Rails日次集計を先に確認してから、staging専用出力先へ対象日を手動出力する。
8. 同じ対象日を再出力し、aggregation key重複なし・行数不変を確認する。
9. 自動出力が`false`、出力状態が予期せず増えていないことを再確認する。
10. ID・Secret・フォーム入力値を表示せず、成功／失敗と匿名集計値だけを記録する。

手動出力・復旧コマンドは[Google Sheets連携運用手順](lp_analytics_google_sheets.md)を使用する。

## 6. 性能評価の現状

- `AnalysisQuery`はgrouped countを先に取得し、訪問件数を増やしてもquery本数が増えないことを自動テストで保証する
- `DailyAggregationQuery`は選択訪問と訪問別event合計の2 CTEから1回で集計し、event種別ごとのjoinを行わない
- 訪問には`lp_identifier + started_at`と流入・UTM・端末別index、eventには`visit + type + value`と重複防止indexがある
- 最近のコンバージョンは20件ずつ、最大100件でページングし、訪問をpreloadする
- Sheets書込みは行ごとのrequestではなく`spreadsheets.values.batchUpdate`へまとめる

想定月間訪問・event件数と応答時間目標は未確定である。現時点では小規模なstagingデータだけなので、代表データ量での`EXPLAIN (ANALYZE, BUFFERS)`とworker占有時間の測定は未実施とする。データ量と目標を確定した後に測定し、結果なしに別集計基盤や不要なindexを追加しない。

## 7. production rolloutチェックリスト（未実施）

次はすべて事前承認を得てproductionで実施する。#1033のstaging成功だけを理由に自動実行しない。

- [ ] deploy対象commit、migration、rollback image、実施時間、担当者を確定する
- [ ] DB migrationを先に適用し、既存LP・登録・お問い合わせが継続することを確認する
- [ ] app / workerがproduction用env fileを参照し、必須keyが存在することを値非表示で確認する
- [ ] production role・Secret・Spreadsheet・サービスアカウントの環境一致を二者で確認する
- [ ] production専用Spreadsheetをread-onlyで確認する
- [ ] 対象日を限定した初回手動出力を承認後に実行する
- [ ] Rails DB・system_admin・production Spreadsheetの訪問、CTA、フォーム、完了、CV率を突合する
- [ ] GTM、Meta広告、Microsoft Clarityの実環境発火を各管理画面で確認する
- [ ] 02:20 JST前に自動出力flagを有効にする場合は、無効化手順と監視担当を確認する
- [ ] 初回自動出力後に対象直近7日、重複key、失敗状態、worker稼働を確認する
- [ ] CloudTrailで対応production roleによる対応SecretのAPI eventだけを確認する

## 8. 無効化・rollback

- 問題時は`LP_ANALYTICS_SHEETS_EXPORT_ENABLED=false`にしてworker containerを承認後に再作成し、Google Sheets自動出力だけを止める
- Rails DBへのLP行動保存、店舗登録、お問い合わせは停止しない
- Spreadsheetを手修正せず、Rails DBを正として原因修正後に対象日・期間を再出力する
- application rollback時も追加済みテーブルを直ちにdropせず、LP・登録・お問い合わせの継続を優先する
- production container再作成、出力先変更、権限変更、Secret rotationは個別承認を得る

## 9. #1033の残項目

staging横断シナリオ、実Sheets出力、冪等再出力、個人情報・log監査、worker再起動後確認は完了した。残るのは次のproductionまたは運用判断を要する項目である。

- production初回手動出力とRails DBとの数値突合
- production自動出力の有効化・初回02:20 JST確認・無効化復旧確認
- production上のGTM・Meta広告・Microsoft Clarity実発火確認
- 想定データ量と応答時間目標の確定後のSQL実行計画・worker所要時間測定

productionへ触れないPRではIssueをcloseせず、これらを未実施として明記する。
