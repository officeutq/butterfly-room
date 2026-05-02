# Onboarding 設計

## 1. 概要

店舗管理者向けに、初期セットアップを案内するオンボーディングUIを提供する。
Bootstrap Popover と Stimulus により、対象要素をハイライトしながら次の操作を示す。

---

## 2. 対象Controller

```text
onboarding_controller
```

---

## 3. 基本動作

1. 現在stepを受け取る
2. stepに応じた対象要素を探す
3. 対象要素をハイライトする
4. 必要ならスクロールする
5. Popoverで説明を表示する
6. step更新イベントを受けたら再描画する

---

## 4. Step更新

window event:

```text
onboarding:update
```

share_controller などがオンボーディング進行を通知する。

---

## 5. Turbo対応

`turbo:before-cache` で以下をcleanupする。

- highlight
- Popover

Turbo cache に古いPopoverやハイライトが残らないようにする。

---

## 6. 想定ステップ

```text
invite_cast
create_invite
go_dashboard
setup_drinks
```

用途:

- キャスト招待へ誘導
- 招待URL作成へ誘導
- ダッシュボードへ戻す
- ドリンク設定へ誘導

---

## 7. 画像

Controller values で画像URLを受け取る。

```text
inviteCastImageUrl
createInviteImageUrl
goDashboardImageUrl
setupDrinksImageUrl
```

Popover内で説明画像として表示する想定。

---

## 8. 設計上の注意点

- 対象DOMには `data-onboarding-target-element` を付与する
- 画面遷移後に対象要素が存在しない場合、何も表示しない
- fixed header / fixed subnav があるため、scrollIntoView後の表示位置に注意する
- Bootstrap Popover の破棄漏れに注意する
