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

## 残る環境確認（#1294を閉じる前）

#1291〜#1293の管理統合はこの作業ではステージング・本番へ反映しない。必要な環境反映の範囲を確認し、次の差分を利用者と確認して結果を追記する。新規作成や閉鎖には検証専用ブースを使う。

- 店舗管理者・システム管理者の新しいブース情報で、実配信の強制終了を行い、配信者への通知・映像音声停止・リザルト、管理者の同じ情報画面への復帰を確認する。PC・スマートフォン実機を含める。
- 実機でヘッダー選択、情報画面のボタン・確認の取消／確定、閉鎖後の履歴と戻る、新規作成カードの表示・操作を確認する。
- 上限到達のAWS障害は実環境に意図的に起こさず、代替応答・DB試験の結果を利用する。実機・実IVSで未確認の障害条件はその区別を残す。

上記の環境確認が残る間は#1294・親#1290をDoneにしない。環境反映と必要な確認後に、この文書・Issueへ使用役割、端末、ブラウザー、対象コミット、結果を追記する。
