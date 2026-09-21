# ブース管理統合の横断検証（#1290 / #1294）

2026-09-18。管理操作・閉鎖済み履歴・新規作成カード・旧一覧廃止を、共通選択と配信制御へ接続した結果を記録する。基準はmain `38f3885298dfb5eefa1939fb57c58b63db2aabf8`。この文書と撮影スクリプトを追加したコミットでは、アプリの実行コード・DB構造は変更しない。

## 実装と先行確認

| Issue / PR | mainへの取り込み | 内容 |
| --- | --- | --- |
| #1291 / #1348 | `1cc91b45` | ブース情報の強制終了・閉鎖、対象ブースだけの切断結果 |
| #1292 / #1349 | `2fbab33e` | 閉鎖済み情報・履歴・共有禁止、キャストの認可済み直接閲覧 |
| #1293 / #1350 | `38f38852` | 独立した新規作成カード、旧管理一覧廃止、店舗選択・戻り先 |

共通選択は[#1277のステージング・実機確認](../ops/current_selection_staging_verification.md)、配信基盤は[#1340の検証](publisher_retry_validation.md)と[環境記録](../ops/publisher_retry_staging_verification.md)を参照する。完了済みの3役割×PC／スマートフォンの配信・選択確認を未完了へ戻さない。ただし、旧画面での実機確認を、新しい情報画面の確認済み実績として転記しない。

## 要件と試験の対応

テスト名はリポジトリ内のファイル名。撮影フローは `tests/manual_capture/booth_management_flow.cjs`。AWSの代替応答を使うテストと実IVSを混同しない。

| 境界 | 根拠・今回の確認 |
| --- | --- |
| 管理者の閉鎖済み候補、現役1＋閉鎖1、閉鎖のみ0／1／複数、D01 | `current_selection_service_test.rb`、`current_selection_test.rb`、`current_selection_ui_test.rb` |
| 役割・所属・権限喪失、キャストの閉鎖済み選択禁止 | 同上、`closed_booth_information_test.rb`、撮影フローの3役割 |
| 情報→強制終了→同じ情報→閉鎖→同じ情報→履歴→情報 | `booth_management_test.rb`、撮影フローの店舗管理者／システム管理者×2画面幅 |
| 閉鎖後の共有・編集・準備・開始拒否、履歴0件・過去リザルト | `closed_booth_information_test.rb`、`booth_info_sharing_test.rb`、`booth_sharing_test.rb`、`booth_enter_test.rb` |
| 情報・履歴のB追従、編集・準備から閉鎖済みB情報、未保存キャンセル | `current_selection_ui_test.rb`、`preparation_selection_test.rb`、JavaScriptの共通選択テスト。撮影では情報→閉鎖済み情報と履歴の往復 |
| 強制終了の状態条件・確認・古いフォーム・ID／世代 | `booth_management_test.rb`、`admin_booth_force_end_test.rb`。撮影では店舗・ブース・配信タイトルを含む確認の取消／確定 |
| 終了通知・未消化返却・競合・重複防止 | `publisher_ending_test.rb`と#1340の配信試験。今回のブラウザー撮影に視聴者・ドリンクは用意しない |
| 切断成功／再試行中／最終失敗、配信中と取消の切断待ち併存 | `booth_management_test.rb`。保存済み3状態と閉鎖後も履歴が利用可能なことを撮影 |
| A表示に本人の別ブースBを混在させない。初期HTML・GET・通知の一致 | `booth_management_test.rb`。表示は`scope=booth`、次回開始制限は人物＋対象ブースという既存範囲を維持 |
| 通知未達・GET失敗・遅い旧応答、有限取得後の未確認案内 | JavaScriptの`publisher_result_test.cjs`。撮影では保存済みretryingを読み続け、有限回後に再読込案内となることを確認 |
| 閲覧・再読込で切断を実行せず回数を戻さない、復旧ボタン・旧POSTなし | `booth_management_test.rb`、#1340の専用ボタン・経路撤去試験。撮影後に過去履歴・未確認接続の属性を比較 |
| 本人配信中・離席中固定、別タブ・端末・再ログイン | 共通選択テストと#1277の実機結果を参照。管理画面用の固定解除例外は追加しない |
| 新規作成カード、ブース0件・全閉鎖、店舗未選択・店舗なし、本人固定 | `booth_dashboard_navigation_test.rb`。#1293のブラウザー作成8件・初回担当4件の結果もPR #1350を参照 |
| 作成POST・初回担当者・店舗認可、作成後／戻るはダッシュボード | `booth_create_with_cast_assignment_test.rb`、`booth_dashboard_navigation_test.rb`。今回は所属店舗と戻る操作を撮影 |
| 旧2一覧GET・旧return_to・モーダル通常アクセス・エラー復帰 | `admin_booths_index_test.rb`、`current_selection_entry_test.rb`、`current_selection_ui_test.rb`、撮影フロー |
| 公開一覧・詳細・共有・お気に入り・履歴・店舗一覧を残す | ルーティングと上記の閲覧テスト。管理一覧GETだけを廃止。全体の回帰はCIで確認 |
| 選択外公開カードは視聴、選択中管理者は視聴／配信、非公開店舗は準備・開始不可 | `public_booth_card_selection_test.rb`、`preparation_selection_test.rb`、`booth_enter_test.rb`、#1277の実機結果 |

## 今回のローカル確認

結果・実行コマンド・画像の保存先は[撮影記録](../user_manual/booth_management_capture.md)に記載する。

- 関連Rails：205件・3,250項目、失敗・エラー・省略なし（seed 61911）。下記コマンドで実行した。
- `npm run test:js`：204件成功。今回、通信例外・HTTP失敗・不正な状態の3ケースを追加し、対象ブースのGETを4回で停止、AWS切断失敗と断定せず再読込案内、更新要求なしを確認した。
- 撮影：Chromium `149.0.7827.55`、3役割×2画面幅の6組合せで成功。実行ID `106e7a54`。強制終了・閉鎖4件、AWS代替切断4回、閉鎖済み3状態×6組合せの履歴往復を確認した。
- RubyのRuboCop、変更した撮影JavaScriptの構文、`git diff --check`を確認。アプリのJavaScript／CSSを変更していないため、今回の資産ビルドは実施しない。
- 文書22ファイルの相対リンク・画像参照178件に欠落なし。既存の役割別撮影スクリプトは旧カード・一覧の期待値を修正し構文確認した。店舗編集・招待・精算を含む一括撮影は対象外のため実行せず、今回追加した専用フローで管理統合を確認した。

```powershell
docker compose exec -T -e RAILS_ENV=test -e ACTUAL_PUBLISHER_CONTROL_ENABLED=false app bundle exec rails test test/services/current_selection_service_test.rb test/controllers/concerns/current_selection_test.rb test/integration/current_selection_ui_test.rb test/integration/current_selection_entry_test.rb test/integration/preparation_selection_test.rb test/integration/public_booth_card_selection_test.rb test/integration/cast/booth_management_test.rb test/integration/cast/closed_booth_information_test.rb test/integration/cast/booth_navigation_test.rb test/integration/cast/booth_info_sharing_test.rb test/integration/booth_sharing_test.rb test/integration/booth_enter_test.rb test/integration/admin/booth_dashboard_navigation_test.rb test/integration/admin/booth_create_with_cast_assignment_test.rb test/integration/admin_booth_force_end_test.rb test/integration/admin_booths_index_test.rb test/integration/cast/publisher_ending_test.rb test/services/stream_sessions/publisher_ending_test.rb test/services/ivs/disconnect_publisher_connection_service_test.rb
```

既存の旧方式テストも含むため、実行時の既定値をCIと同じfalseにする。新方式を検証するケースではテスト自身がtrueに切り替える。初回は開発用のtrue設定を引き継ぎ、旧方式前提の6失敗・7エラーが発生した。既定値を明示した上記の実行では成功した。開発用設定ファイルは変更していない。撮影は新方式をtrueで有効化している。

ブラウザーはChromiumの1440px／390px幅。390pxはスマートフォン幅の画面・操作確認であり、実機Safariの代替とはしない。毎回新しい専用テストDBを作り、架空の利用者・店舗・ブースを使う。AWS SDKは代替応答、ジョブはテスト用キューとし、既存の開発DB・実Stage・実端末のカメラ／マイクは操作しない。

## ステージング反映（2026-09-22）

利用者の依頼を受け、2026-09-22 06:59 JSTにmain `7d2f382665076001ab6002bc9d0e3830ea4412f8` を[ステージング](https://staging.butterflyve.jp/)へ反映した。#1291〜#1293の管理統合に加え、#1353のブース説明と#1355の店舗編集の説明を含む。[対象mainのCI](https://github.com/officeutq/butterfly-room/actions/runs/35659100140)はquality・testとも成功。本番環境は変更していない。

- app・workerを同じ対象コミットのイメージで起動し、ソースを照合。バックグラウンド処理の稼働、失敗ジョブ0件、反映直後のエラーログ0件を確認した。
- DBバックアップを取得・検証した。DB構造の変更・未適用マイグレーションはなく、マイグレーション・seed・履歴補完は実行していない。店舗・ブース・配信履歴・接続・所属・ドリンク・売上台帳など12モデルの件数・全属性のハッシュが反映前後で一致した。
- 既存の環境設定・未追跡ファイルを保持し、旧イメージを復旧用に保存した。
- HTTPSの正常性確認、トップページ、ログインページ、CSSと関連JavaScriptは200。トップページの初回確認では15秒のタイムアウトが1回あり、再試行で200、その後の再確認も200・約0.35秒で応答した。
- 新しい管理画面のテンプレート・操作先・カード・説明文と、旧管理一覧テンプレートの撤去を確認した。これらは稼働・ソース・配信ファイルの確認であり、次の利用者による実機確認とは区別する。

## 利用者による実機確認（2026-09-22）

ステージング反映後、利用者から次の4項目すべて正常との報告を受けた。上記コミットの新しい管理画面での結果として記録し、2026-09-18のAWS代替応答による撮影結果と区別する。

| 操作 | 利用者が確認した結果 |
| --- | --- |
| 新規作成 | 「ブース新規作成」カードから作成し、ダッシュボードへ戻れる |
| 強制終了 | 別端末・別アカウントの配信を管理者の「ブース情報」から強制終了し、配信者側の通知・映像音声停止・リザルトを確認できる |
| 閉鎖 | 同じブース情報から閉鎖でき、共有・編集が非表示になる |
| 履歴 | 閉鎖後も配信履歴を閲覧でき、ヘッダーから閉鎖済みブースを選び直せる |

利用者から、配信側はiPhone 15 Proのキャスト、強制終了・閉鎖を行う管理側はPCのシステム管理者との申告を受けた。ブラウザー名は今回未申告。新規作成・履歴の正常報告も上表へ記録し、過去の#1277・#1340の役割別実機結果から未申告の組合せを補完しない。

| 担当 | 端末・役割 | 結果 |
| --- | --- | --- |
| 配信側 | iPhone 15 Pro・キャスト | 配信し、強制終了後の通知・映像音声停止・リザルトを確認 |
| 管理側 | PC・システム管理者 | 新しいブース情報から強制終了・閉鎖を確認 |

## 残る実機確認

スマートフォンで店舗管理者として、新規作成→ダッシュボード、ブース情報から強制終了、閉鎖、閉鎖後の履歴・ヘッダー再選択の4項目を確認する。今回のiPhoneは配信者側の確認であり、スマートフォンの管理画面を操作した結果には含めない。この組合せで、今回追加された管理画面のスマートフォン操作と店舗管理者の実機導線を補う。

確認ダイアログの取消操作は今回の報告に含まれないため、ローカル撮影フローの取消／確定試験の結果を参照する。AWS障害による上限到達は実環境に意図的に起こしておらず、代替応答・DB試験の結果を利用する。残る実機結果の追記とPR #1351の確認・マージが完了するまで#1294・親#1290は完了にしない。
