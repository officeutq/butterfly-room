# cast 通常操作撮影結果

この文書は、第5回作業で取得した cast（配信者）向け通常操作スクリーンショットの撮影記録です。撮影は development（開発環境）で実行し、production（本番環境）の挙動は変更していません。

## 撮影コマンド

```bash
docker compose exec -T app bin/rails manual_capture:prepare
npm run manual:capture:cast
```

cast（配信者）は `manual_capture:prepare` が作成する `manual+cast@example.test` を使用しました。固定パスワードは内部撮影用情報のため、読者向けマニュアル本文には記載しません。

## 撮影した画面と実際の遷移先

| 対象 | 開始 URL / 操作 | 実際の遷移・結果 |
| --- | --- | --- |
| dashboard（ダッシュボード） | `/dashboard` | cast（配信者）向けカード一覧を表示 |
| ブース一覧 | `/cast/booths` | `マニュアル撮影用ブース` と `マニュアル撮影用サブブース` を表示 |
| ブース情報 | `/cast/booths/:id` | ブース名、キャスト、所属店舗、共有・編集・配信履歴導線を表示 |
| ブース編集 | `/cast/booths/:id/edit` | フォーム表示、説明文入力、更新後 `/dashboard` |
| current booth（現在選択中のブース）確認 | `/cast/booths` | 編集画面表示で session（セッション）に入ったブースが「選択中」と表示 |
| 配信履歴 | `/cast/booths/:booth_id/stream_sessions` | 終了済み stream session（配信セッション）がないため空状態 |
| 配信画面入口 | `/booths/:id/enter` | `StreamSessions::StartService` で standby（配信準備中）を作成し、`/cast/booths/:id/live` へ遷移 |
| pending drink orders（未消化ドリンク） | `/cast/stream_sessions/:id/pending_drink_orders` | 「未消化のドリンクはありません」を表示 |

## 保存したスクリーンショット

### dashboard（ダッシュボード）

- `images/cast/dashboard/01_dashboard.png`

### ブース一覧・ブース情報

- `images/cast/booths/01_index.png`
- `images/cast/booths/02_show.png`
- `images/cast/booths/03_index_current_booth.png`

### ブース編集

- `images/cast/booth_edit/01_edit_form.png`
- `images/cast/booth_edit/02_edit_filled.png`
- `images/cast/booth_edit/03_after_update_dashboard.png`

### 配信画面入口

- `images/cast/live/01_live_standby_initial.png`

### 配信履歴

- `images/cast/stream_sessions/01_index_empty.png`

### pending drink orders（未消化ドリンク）

- `images/cast/drink_orders/01_pending_empty.png`

## 実行しなかった危険操作

- 「配信開始」ボタンはクリックしていません。
- 「配信終了」ボタンはクリックしていません。
- 席外し / 復帰の status（状態）変更は実行していません。
- drink order（ドリンク注文）の消化は実行していません。
- 実カメラ、実マイク、実 IVS join（Amazon IVS への参加）、実 publish（配信送信）は実行していません。
- Banuba / DeepAR（画面加工）の本格操作は実行していません。
- Stripe（決済）、SMS（ショートメッセージ）、Google Docs 連携は対象外です。

## 外部サービス依存の扱い

- `manual_capture:prepare` は Booth（ブース）に疑似 `ivs_stage_arn` を設定します。
- `/booths/:id/enter` は `Booths::EnterAsCastService` と `StreamSessions::StartService` により DB（データベース）上の standby（配信準備中）を作るだけで、AWS（Amazon Web Services）を呼びません。
- Playwright（ブラウザ自動操作）側では `stream_sessions/:id/ivs_participant_tokens` へのアクセスをブロックし、誤って participant token（参加トークン）取得に進まないことを確認しています。
- fake media（疑似カメラ・疑似マイク）用に Chromium の `--use-fake-device-for-media-stream` と `--use-fake-ui-for-media-stream` を cast spec（テスト定義）内で指定しています。
- `BANUBA_CLIENT_TOKEN` や `DEEPAR_LICENSE_KEY` がなくても、今回の撮影範囲では失敗しない画面表示までに留めています。

## 確認した主な実コード

- `config/routes.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/cast/base_controller.rb`
- `app/controllers/cast/booths_controller.rb`
- `app/controllers/cast/current_booths_controller.rb`
- `app/controllers/cast/booths/stream_sessions_controller.rb`
- `app/controllers/cast/stream_sessions_controller.rb`
- `app/controllers/cast/drink_orders_controller.rb`
- `app/controllers/booths_controller.rb`
- `app/views/dashboard/show.html.erb`
- `app/views/cast/booths/index.html.erb`
- `app/views/cast/booths/show.html.erb`
- `app/views/cast/booths/edit.html.erb`
- `app/views/cast/booths/live.html.erb`
- `app/views/cast/booths/stream_sessions/index.html.erb`
- `app/views/cast/stream_sessions/_pending_drink_orders.html.erb`
- `app/javascript/controllers/ivs_publisher_controller.js`
- `app/javascript/controllers/ivs_publisher/api_client.js`
- `app/javascript/controllers/ivs_publisher/media_state.js`
- `app/services/booths/enter_as_cast_service.rb`
- `app/services/stream_sessions/start_service.rb`
- `app/services/stream_sessions/status_service.rb`
- `app/services/stream_sessions/end_service.rb`
- `app/services/ivs/create_participant_token_service.rb`
- `test/integration/cast/booth_update_test.rb`
- `test/integration/cast/booths_two_screens_test.rb`
- `test/integration/cast/booths_select_modal_test.rb`
- `test/integration/cast_booth_selection_return_test.rb`

## 未確認点

- 実配信開始から終了までの完全フロー。
- live（配信中）/ away（席外し）への status（状態）変更。
- 実カメラ、実マイク、実 IVS join、実 publish。
- Banuba / DeepAR の token / license 設定済み環境での画面加工操作。
- customer（視聴者）によるドリンク送信から cast（配信者）による消化までの完全フロー。
- 終了済み stream session（配信セッション）がある状態の配信履歴。
- mobile（スマートフォン幅）での cast 操作。
