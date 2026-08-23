# stores/lp_202609 公開準備チェックリスト

## 1. 目的と安全境界

`/stores/lp_202609`の表示、導線、行動分析を横断確認し、Meta広告の遷移先を`/stores/lp_202607`から安全に切り替えられる状態にする。

- Rails DBを行動分析の正本とし、Googleスプレッドシートは匿名の日次集計の共有先とする
- stagingとproductionのデータ、Secret、Spreadsheetを混在させない
- productionのフォーム送信、Spreadsheet書込み、広告遷移先変更は、実施日時と担当者を記録してから行う
- `/stores/lp_202607`は削除せず、比較・rollback用に維持する
- 売上、配信、店舗登録等のPhase1業務仕様は変更しない

行動分析のデータ照合とGoogleスプレッドシート操作は、[LP行動分析 横断検証・rollout手順](lp_analytics_validation.md)および[Google Sheets連携運用手順](lp_analytics_google_sheets.md)に従う。

## 2. 2026年8月23日 ローカル確認結果

確認対象commitは`968c8a5dfcb7463544b49392640f2d91ad3da59f`である。

### 自動確認

| 確認 | 結果 |
| --- | --- |
| `npm run build:css` | 成功。既存のSass非推奨警告のみ |
| `npm run test:js` | 31件成功 |
| `docker compose exec -T app bin/rails test` | 893 runs、6019 assertions、失敗・error・skipなし |
| `docker compose exec -T app bundle exec rubocop` | 512 files、違反なし |
| `docker compose exec -T app bundle exec brakeman --no-pager` | security warning・errorなし |
| `docker compose exec -T app bin/importmap audit` | 脆弱性検出なし |

Rails全体testには、202609版のroute・View・attribution引き継ぎ、FAQからの復帰、LPイベント・完了、system_admin集計、Googleスプレッドシート日次集計・出力が含まれる。

### ブラウザ表示

| 画面 | 確認結果 |
| --- | --- |
| PC 1440 x 900 | ヘッダー、ファーストビュー、本文、CTA、FAQ、フッターを確認。横スクロールなし |
| タブレット 768 x 1024 | 主CTAを最初の画面内で確認。画像・本文・1列scene表示に崩れなし |
| スマートフォン 390 x 844 | 固定CTA、全scene、最終CTA、FAQ、フッターを確認。横スクロールなし |

共通して次を確認した。

- 10画像が読込み済みで、202609版の主要画像に代替テキストがある
- 店舗登録、お問い合わせ、FAQ、ページ内リンクが正しい遷移先を持つ
- FAQ、店舗登録、お問い合わせから`/stores/lp_202609/return`を経由して、流入時の`ref`を保持したLPへ戻る
- 店舗登録・お問い合わせフォームへ`from=stores_lp_202609`が引き継がれる
- JavaScriptでenhanced classが付与された場合だけreveal animationを適用し、JavaScript無効時も主要本文とCTAを非表示にしない
- 202609版のWebP画像5件はすべて約150KB以下
- 202607版は専用layoutとstylesheetを利用し、スマートフォン幅でも崩れ・横スクロールがない
- ローカル確認中のブラウザconsole errorはない

## 3. staging確認

2026年8月23日18時57分（JST）の再確認では、`https://staging.butterflyve.jp/up`がHTTP 200へ復旧した。Basic認証なしで`https://staging.butterflyve.jp/stores/lp_202609`へアクセスするとHTTP 401と`WWW-Authenticate: Basic realm="Butterfly Room Staging"`が返り、認証境界も有効だった。19時台には認証済みChromeで実画面と主要導線を確認した。

staging復旧またはデプロイは、[ステージング環境デプロイ手順](../staging/deployment.md)と[ステージング構築後チェックリスト](../staging/post_apply_checklist.md)に従い、権限を持つ担当者が実施する。

次を確認する。

- [x] `/up`がHTTP 200で正常応答する
- [x] Basic認証なしのLPアクセスをHTTP 401で拒否する
- [x] `/up`と認証拒否応答に`X-Robots-Tag: noindex, nofollow`が付く
- [ ] AWS上でTarget Groupがhealthyである
- [x] 認証後の画面で`noindex, nofollow`とGTM scriptなしを確認する
- [x] 202609版をPC 1440 x 900、タブレット 768 x 1024、スマートフォン 390 x 844で表示できる
- [x] 202609版の各画面幅で横スクロールと画像読込み失敗がない
- [x] 202607版をPC、タブレット、スマートフォンで専用layout・stylesheetのまま表示できる
- [x] 202609版から店舗登録、お問い合わせ、FAQへ遷移し、LPへ戻れる
- [x] 戻った202609版で`ref`と`from=stores_lp_202609`の導線を保持する
- [x] staging専用の検証値で店舗登録・お問い合わせを各1件だけ完了する
- [x] LP表示、CTA、フォーム表示、完了が`stores_lp_202609`としてRails DBへ記録される
- [ ] stagingでスクロール・主要セクション到達をRails DBと照合する
- [x] system_adminと同じ集計経路で202607版と202609版を分けて確認できる
- [x] staging用Googleスプレッドシートへのread接続と移行前状態を確認する
- [x] staging用Googleスプレッドシートの日次出力をRails DBと照合できる
- [ ] 同一流入30分以内、30分経過後、UTM変更、referral code変更、reload、複数tabを[横断検証手順](lp_analytics_validation.md)どおり確認する
- [x] 自動出力が`false`のままで、appとworkerが同じimageで稼働している

検証用店舗名、氏名、メールアドレス等へ個人の実情報を使わない。production用Spreadsheet、production Secret、production DBへstagingデータを書き込まない。

2026年8月23日19時台に、`form_submission_20260823_1910`で店舗登録1件、`contact_submission_20260823_1910`でお問い合わせ1件を完了した。`butterfly_room_staging` DBで、それぞれCTAクリック訪問、フォーム表示訪問、完了1件と業務recordへの紐づけ1件を確認した。system_adminで使用する`AnalysisFilter`と`AnalysisQuery`でも、LPを`stores_lp_202609`、同日、各`utm_content`で絞った完了件数が一致した。検証用入力値、業務record ID、匿名訪問IDは記録しない。

staging用`daily_raw`は旧25列headerと完全一致し、新58列への移行dry runが成功した状態から実出力した。最初の訪問日は2026年8月9日、自動出力は`false`である。

2026年8月23日19時台の初回出力では58列への移行自体は成功したが、同じ対象日の202607版と202609版を順番に出力すると、後のLP出力が先のLP行を空欄化する不具合を検出した。原因は`IdempotentWriter`の古い行を空欄化する条件が対象日だけで、対象LPを含んでいなかったことである。空欄化対象を対象日・対象LPの両方で限定し、同日の別LP行を維持する回帰testを追加したcommit `0c8a8cf`をstagingへ反映した。

修正後に2026年8月9日から22日までと23日を再出力し、15日分・2LPの出力状態30件がすべて`succeeded`となった。`daily_raw`は58列、headerを含む12行、管理行11件（202607版6件、202609版5件）で、aggregation keyと`exported_at`以外の全集計値がRails DBと一致した。重複key、部分行、メール形式の値、秘密鍵文字列は0件だった。23日を再出力しても総行数12・管理行11のままで、202607版2行と202609版5行を維持した。appとworkerは同じ修正版imageで稼働し、自動出力は`false`のままである。

202607版は1440 x 900で23pxの横方向overflowを確認した。タブレット・スマートフォンでは横方向overflowはなかった。このPRでは202607版のView、layout、CSSを変更していないため既存挙動として記録し、202609版の公開準備とは分けて扱う。

## 4. production公開前確認

- [ ] 公開対象commitとデプロイimage tagを記録する
- [ ] rollback用として直前の正常image tagと`/stores/lp_202607`を確認する
- [ ] production URLで202609版と202607版がともに表示できる
- [ ] canonical URL、画像、登録・お問い合わせ・FAQの遷移先を確認する
- [ ] productionでは書込みを伴わない範囲で、`from`、UTM、referral codeのURL引き継ぎを確認する
- [ ] 実送信が必要な場合は、検証用データ、実施時刻、削除または無効化方法を事前承認する
- [ ] Googleスプレッドシートの58列header移行と出力対象期間を[連携運用手順](lp_analytics_google_sheets.md)どおり承認する
- [ ] Meta広告URLへ`utm_source`、`utm_medium`、`utm_campaign`、`utm_content`を設定し、`utm_content`欠損を減らす
- [ ] 広告切替担当者、承認者、実施予定時刻、確認担当者を決める

## 5. Meta広告切替記録

切替当日は、次を運用記録またはIssueコメントへ残す。

| 項目 | 記録値 |
| --- | --- |
| 切替日時（JST） |  |
| 対象campaign・広告set・広告 |  |
| 変更前URL | `/stores/lp_202607` |
| 変更後URL | `/stores/lp_202609` |
| UTM template |  |
| 実施者 |  |
| 承認者 |  |
| production確認結果 |  |
| rollback判断者 |  |

切替直後は実際の広告リンクから1回だけアクセスし、URL、端末表示、LP識別子、UTM、主CTAの遷移先を確認する。広告の審査・preview・自動アクセスに見えるPC訪問は、実利用のスマートフォン・タブレットと分けて記録する。

## 6. rollback

重大な表示崩れ、主CTAの遷移不能、202607版との計測混在、productionの外部送信先誤りを確認した場合は、効果比較を待たずrollbackする。

1. Meta広告の遷移先を`/stores/lp_202607`へ戻し、変更時刻と理由を記録する
2. 戻した広告リンクから202607版の表示と店舗登録CTAを確認する
3. application不具合の場合は直前の正常imageへ戻す。202609版のroute、DB履歴、集計データを削除しない
4. Googleスプレッドシート出力だけに問題がある場合は、自動出力を停止し、Rails DBを正本として保持する
5. 影響期間、対象campaign、訪問・完了件数、再公開条件をIssueへ記録する

## 7. 公開後の比較

### 比較基準

202607版の基準期間は2026年8月9日から8月22日とする。Meta広告経由のスマートフォン・タブレットは345訪問、25%到達48.1%、最下部CTA到達20.0%、登録CTAクリック4.9%、登録フォーム表示17訪問、登録完了6訪問、登録CV率1.7%だった。

PC 1,932訪問は25%到達率・最下部到達率がともに0.7%で、`utm_content`欠損も多かった。原因は断定せず、主評価から分けて確認する。

### 期間と指標

- 切替日は不完全な1日として主比較から除外する
- 翌日から3日分で表示、CTA、計測欠損等の技術的異常を確認する
- 7日分で中間確認する
- 14日分を主比較期間とする
- スマートフォン・タブレットの訪問が300未満の場合は、最大28日まで延長する

202607版と202609版を同じ期間条件で、`device_type`、`utm_content`、LP識別子別に比較する。指標はLP訪問、25%到達、最下部CTA到達、登録CTAクリック、登録フォーム表示、登録完了・CV率、お問い合わせCTAクリック、フォーム表示、完了とする。

### 判断

- 重大な技術的不具合は即時rollback対象とする
- 効果の判断は、主比較期間のスマートフォン・タブレットを中心に行う
- PCと`utm_content`欠損訪問は別segmentとして併記し、合算値だけで判断しない
- 14日分と必要訪問数を満たす前に、短期変動だけで優劣を確定しない
- 継続、修正、202607版へ戻す判断と、その根拠となる数値をIssueへ残す

## 8. 公開完了記録

- [ ] staging横断確認完了日時と担当者
- [ ] productionデプロイ日時、commit、image tag
- [ ] Meta広告切替日時と対象campaign
- [ ] 切替直後の表示・CTA・計測確認
- [ ] 3日、7日、14日の比較結果
- [ ] 継続・修正・rollback判断
