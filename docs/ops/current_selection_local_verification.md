# ブース・店舗選択のローカル確認（#1274〜#1277）

2026-09-16。選択ルール、ヘッダー、配信準備の切替までローカル実装済み。**ステージング・本番への反映は行っていない。** #1274・#1275・#1276は順に重ねた作業ブランチで管理し、マージ前の状態でローカル確認できる。

## 確認済みの範囲

| 契約のケース | 主な確認 | 証跡となるテスト |
| --- | --- | --- |
| C01・C02 | 3役割の0／1／複数、本人配信中・離席中、閉鎖済み込みの固定・候補表示 | current_selection_service_test、current_selection_ui_test |
| C03 | D01のA→Bで未設定維持、B→Aで唯一のブース、必要操作時の自動設定 | current_selection_entry_test、current_selection_service_test |
| C04 | 情報や候補GETでは準備しない。明示的な準備入口だけ作成・再利用 | current_selection_entry_test、publisher_preparation_test |
| C05 | 未保存確認、キャンセル、409・通信失敗時の入力保持、B編集への追従 | selection_switch_controller_test.cjs、ローカルChromiumでPC幅1440px／スマートフォン幅390px |
| C06 | 空き／未配信準備／他者配信中・離席中／閉鎖済み／準備失敗。元の準備とタイトルの保持 | preparation_selection_test、publisher_preparation_test、ivs_publisher_lifecycle_test.cjs |
| C07 | 古い編集・画像・ドリンク・口座フォームの対象一致と拒否、元入力の保持 | current_selection_entry_test、各フォームの既存テスト |
| C08〜C10 | ログイン復帰、招待表示・承認直前、開始成功との競合、D02の成功通知・初回B編集 | cast_invitation_broadcast_guard_test、broadcast_guard_concurrency_test、cast_invitation_flow_test |
| C11 | 無効な選択・権限喪失・本人配信の不整合を空きとして扱わない | current_selection_service_test、preparation_selection_test |
| C12 | 旧キャスト一覧廃止、公開詳細／特定リザルトの対象維持、先読みで準備しない | current_selection_entry_test、current_selection_ui_test、booth_navigation_test |

全41項目の入口との対応は[入口対応表](../design/current_selection_entries.md)を参照する。Rubyの全体テストとJavaScriptテストを実行し、外部IVSの応答はテスト用の代替応答で確認した。ブラウザー確認もローカルのテストDBを利用し、開発用の業務データ、ステージング・本番DBを変更していない。

ローカルの開発用Webアプリでは`ACTUAL_PUBLISHER_CONTROL_ENABLED=true`を有効にした。Rails全体テストは既存の旧方式の検証を含むため、実行環境の既定値をfalseにし、新方式のテスト内で明示的にtrueへ切り替える。

```powershell
docker compose exec -T -e RAILS_ENV=test -e ACTUAL_PUBLISHER_CONTROL_ENABLED=false -e PARALLEL_WORKERS=1 app bundle exec rails test
npm run test:js
git diff --check
```

## ローカルでの主な確認手順

1. 複数ブースを操作できる利用者でダッシュボードを開く。ヘッダーのブース名から選択し、ブース情報・編集・履歴の対象が一致することを確認する。
2. 編集画面で値を変更し、ヘッダーから別ブースを選ぶ。破棄確認のキャンセルでは元の入力が残り、続行では新しい対象の編集へ移る。
3. 候補1件では名前のみの表示となることを確認する。店舗A・BとAのブース1件の場合は、店舗Bへ変更後のブース未設定と、ブース情報への移動時のAへの自動設定を確認する。
4. 配信準備AからBへ変更する。空き／準備中BならBの準備へ、他者配信中／閉鎖済みBならB情報へ移る。Aの保存済みタイトルと未開始の準備は残る。
5. 本人の配信中・離席中はブース・店舗の切替導線が出ないこと、配信終了後は選択を維持して切替可能になることを確認する。

## 未実施・後続

- #1277：物理的なPC・スマートフォン、別端末、実IVSの映像・音声を伴う今回の選択改修の横断確認。ブラウザー幅の変更や代替応答テストを実端末・実IVSの確認済みとは扱わない。
- #1278：全操作マニュアル・撮影スクリプト・画像の更新。旧ブース一覧を前提にした撮影手順は後続で差し替える。
- #1251〜#1253：管理用店舗情報とダッシュボード改修。#1291〜#1294：管理操作、閉鎖済み情報の操作表示、旧管理一覧の撤去・新規作成カード。
- 今回の変更のマージ、ステージング・本番への展開は未実施。#1255と横断確認Issueは完了扱いにしない。
