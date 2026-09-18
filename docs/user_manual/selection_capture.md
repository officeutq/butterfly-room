# ブース・店舗選択の撮影記録（#1278）

対象は2026-09-16のローカル実装。選択・情報・編集フォーム・空の配信履歴の画像を、実配信を伴わない専用データで撮影する。利用者から報告された実機・実配信の確認は[別記録](../ops/current_selection_local_verification.md)に分ける。

2026-09-18追記：ブース管理統合後のダッシュボード・強制終了・閉鎖・履歴の画像は[#1294の撮影記録](booth_management_capture.md)を参照する。以下は#1278の選択撮影の記録であり、旧画像を今回の管理統合の確認結果として扱わない。

## 実行環境と準備

既存の開発DBに`manual_capture:prepare`を実行しない。専用の空のPostgreSQLデータベース`butterfly_room_manual_selection`を用意する。下記の`createdb`と`db:schema:load`は初回だけ実行する。既存の同名DBがあれば内容・用途を確認し、初期化し直さない。

```powershell
docker compose exec -T db createdb -U postgres butterfly_room_manual_selection
docker compose exec -T -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection -e DATABASE_URL_TEST=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection app bundle exec rails db:schema:load
docker compose exec -T -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection -e DATABASE_URL_TEST=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection app bundle exec rails runner tests/manual_capture/prepare_selection.rb
```

準備スクリプトはtest環境とDB名を検証する。既存の撮影用アカウント作成処理で3役割と視聴者、2店舗、同じ店舗の未閉鎖ブース2件を用意し、管理者候補の表示用に閉鎖済み1件を加える。疑似Stage識別子は情報表示用であり、実在するStageとして使わない。

別コンテナ・ポートでtestサーバーを起動する。既存開発サーバーのPIDファイルを消さないよう、entrypointを上書きし、PIDファイル名も分ける。AWSには撮影用の無効な認証値を渡す。

```powershell
docker compose run --detach --no-deps --name butterfly-room-manual-selection --publish 127.0.0.1:3102:3102 --entrypoint bundle -e RAILS_ENV=test -e DATABASE_URL=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection -e DATABASE_URL_TEST=postgres://postgres:postgres@db:5432/butterfly_room_manual_selection -e ACTUAL_PUBLISHER_CONTROL_ENABLED=true -e AWS_EC2_METADATA_DISABLED=true -e AWS_ACCESS_KEY_ID=manual-capture-unused -e AWS_SECRET_ACCESS_KEY=manual-capture-unused app exec rails server -b 0.0.0.0 -p 3102 -P tmp/pids/manual-selection.pid
$env:MANUAL_CAPTURE_BASE_URL='http://127.0.0.1:3102'
$env:MANUAL_CAPTURE_SELECTION_ONLY='1'
npm run manual:capture:cast
npm run manual:capture:store_admin
npm run manual:capture:system_admin
docker stop butterfly-room-manual-selection
```

同名コンテナを再利用する場合は`docker start butterfly-room-manual-selection`で起動する。依存するDBコンテナと既存のローカル資産ビルドが必要。撮影はChromium、1440×1400、PC幅で行う。スマートフォン実機の検証ではない。

## 更新画像

各役割の`images/<role>/selection/`に保存する。撮影済みの名前だけ上書きし、既存画像ディレクトリを削除しない。

| ファイル | 内容 |
| --- | --- |
| `01_dashboard.png` | ブース選択後のダッシュボード |
| `02_store_modal.png` | ヘッダーからの店舗選択。店舗管理者・システム管理者のみ |
| `03_booth_modal.png` | ヘッダーからのブース選択。管理者では閉鎖済み候補を含む |
| `04_information.png` | 選択中ブースの情報と編集・履歴導線 |
| `05_edit.png` | 選択中ブースの編集フォーム。保存は行わない |
| `06_history.png` | 選択中ブースの配信履歴。今回は空の状態 |
| `07_information_switched.png` | 情報画面でヘッダーから別ブースへ切替後、表示と選択が一致 |

旧`/cast/booths`がダッシュボードへ戻ることも確認する。管理者の通常操作スクリプトには選択以外の既存処理があるため、今回の撮影では必ず`MANUAL_CAPTURE_SELECTION_ONLY=1`を指定する。キャストのスクリプトは旧一覧・旧準備撮影を除き、この選択撮影に変更した。

## 未撮影・保持する旧画像

- 3役割とも`selection/`以外は過去の画像。今回の撮影済みとして扱わない。旧ブース一覧・旧店舗選択の画像は歴史記録として保持し、操作手順では新画像を参照する。
- 配信中・離席中の固定、候補0／1件、未保存ダイアログ、失敗時表示、準備切替・配信・ドリンク操作は今回の画像に含まれない。複数の未配信候補だけの撮影データであり、実IVS・実カメラ・マイクを使わないため。期待結果は共通手順、確認の証跡は横断確認記録を参照する。
- 管理者の旧一覧、新規作成、各種編集・集計・精算の画像は今回の選択改修の撮影対象外。ヘッダーなどは旧表示を含む。後続の管理画面統合後に#1294等で更新する。
- 閉鎖済み情報画面の「履歴のみ」表示、管理用店舗情報、店舗所属ブース管理、新規作成カードは未実装の後続範囲。仮画像を作らない。

## 2026-09-16の実行結果

上記の専用DBとtestサーバーで、3役割の選択撮影が成功。キャスト6枚、店舗管理者7枚、システム管理者7枚の計20枚を更新した。準備作成・配信開始・実IVS接続・金銭処理は実行していない。開発用業務DB、ステージング・本番は変更していない。

各役割の選択モーダルと情報画面の代表画像を目視確認した。初回の撮影でモーダルの開く途中が写ったため、CSSアニメーションを完了させてから撮影するよう調整して撮り直した。
