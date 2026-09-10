# Onboarding 設計

## 1. 目的と導線

店舗管理者の初回案内を、旧キャスト招待画面に依存せず次の順に行う（#1238）。

**フッターのキャスト招待 → モーダルで共有・コピー → 閉じる → ダッシュボード → ドリンク設定**

進捗は `Store.onboarding_step` に店舗単位で保存する。登録・代行登録で `invite_cast` を保存する。初回店舗設定中と登録・公開完了のサンクスページでは案内を表示せず、その後「店舗ページを見る」で遷移した店舗ページから開始する。未設定・完了・スキップ済みは案内しない。

## 2. 保存状態と案内

| 保存状態 | 案内・更新契機 |
| --- | --- |
| `invite_cast` | フッターの「キャスト招待」を案内する |
| `create_invite` | 招待発行成功で更新。モーダル内説明でメモ・共有・コピーへ案内。旧途中状態もフッターから継続可能 |
| `go_dashboard_for_drinks` | 招待IDと管理権限を確認した共有・コピー成功通知で更新。モーダル内では「閉じる」を表示し、閉じた後にダッシュボードを案内 |
| `setup_drinks` | ダッシュボード到達で更新し、ドリンク設定を案内 |
| `completed` | ドリンク作成・更新成功で完了 |
| `skipped` | その店舗のチュートリアル全体をスキップ |

キャストの承認は待たない。共有・コピー成功は実際の送付や受信を証明しない。共有画面のキャンセルや操作失敗では進めない。招待自体の取消後もフッターから再開できる。既存の進捗をリセットせず、共有済みの店舗に再発行・再共有を強制しない。

## 3. 画面制御

`onboarding_controller` は `data-onboarding-target-element` に一致する対象を強調し、Bootstrap Popover（吹き出し）を表示する。必要に応じて対象までスクロールする。画像は共通レイアウトから渡す。

招待モーダル内では、発行後に共有・コピーボタン、操作後に閉じるボタンへ吹き出しを表示する。吹き出しはモーダル内に配置し、スキップも操作できるようにする。共有後の文言は「共有操作が完了したら、『閉じる』を押して、次の設定に進みましょう。」とする。コピー後はLINE等へ貼り付けて本人に送る案内を表示する。

`app-modal:opening` で背後の強調・吹き出し・予約済みスクロール後表示を停止する。`app-modal:shown` と招待発行結果の通知でモーダル内の案内を描画する。`app-modal:closed` で背後の案内を再描画するため、メモ保存失敗などで閉じられない間はダッシュボードへ誘導しない。店舗選択など、招待以外のモーダルには案内を表示しない。

招待モーダルからの `onboarding:update` には発行・共有処理の結果の進捗と店舗IDを渡す。更新はサーバーで招待の店舗を認可してから行う。旧 `cast_invitation_copied` 通知だけでは進捗を進めない。

共有・コピー操作の成功直後は `cast-invitation:updated` でモーダル内の「閉じる」案内へ切り替える。この通知は保存された進捗を変更せず、完了・スキップ済みの案内も再開しない。

`turbo:before-cache` と切断時には強調・吹き出し・タイマーを破棄する。対象が存在しない画面では吹き出しを表示しない。

## 4. 関連コード

- `app/javascript/controllers/onboarding_controller.js`
- `app/javascript/controllers/cast_invitation_controller.js`
- `app/javascript/controllers/modal_controller.js`
- `app/services/store_cast_invitations/issue_invitation.rb`
- `app/services/store_cast_invitations/update_invitation.rb`
- `app/services/stores/advance_onboarding.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/admin/drink_items_controller.rb`
