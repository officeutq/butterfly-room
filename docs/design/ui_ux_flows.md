# UI / UX Flows 設計

## 1. 概要

本ドキュメントは、Viewファイルから読み取れる主要画面と導線を整理する。

---

## 2. 主要画面グループ

```text
home
store_lps
booths
cast/booths
cast/stream_sessions
dashboard
favorites
wallet
admin
system_admin
legal
profiles
devise
phone_sessions
phone_verifications
```

---

## 3. 未ログイン・LP導線

### 3.1 home

`views/home/_guest_lp.html.erb` が未ログイン向けLPを構成する。

主な役割:

- Butterflyve のサービス説明
- 視聴者登録導線
- ログイン導線
- 店舗向けLP導線
- legal / privacy / terms へのリンク

### 3.2 stores LP

`views/store_lps/show.html.erb` が店舗向けLPである。

主な役割:

- 店舗導入説明
- 店舗登録導線
- 紹介コードrefの引き継ぎ

---

## 4. 視聴者導線

### 4.1 home show

ログイン後の探索画面。

表示モード:

- booths
- stores
- users

検索フォームと切替ナビを持つ。

### 4.2 booth show

視聴ページ。

構成:

- live表示
- waiting表示
- コメント欄
- ドリンクパネル
- お気に入り
- 配信状態partial

viewer_page_controller により live/waiting を切り替える。

### 4.3 favorites

お気に入り一覧。

対象:

- booths
- stores
- users

---

## 5. キャスト導線

### 5.1 cast/booths

キャスト用ブース管理画面。

主な画面:

- index
- edit
- live
- select_modal
- select_modal_redirect

### 5.2 live

キャスト配信画面。

主な構成:

- IVS publisher
- コメント
- 未消化ドリンク一覧
- 操作パネル
- メタ情報
- エフェクト/美顔調整UI

---

## 6. 管理導線

### 6.1 admin

店舗管理者向け。

主な画面:

- booths
- casts
- cast_invitations
- store_admin_invitations
- drink_items
- stores
- settlements
- store_payout_accounts
- metrics
- comment_reports
- store_bans

### 6.2 system_admin

システム管理者向け。

主な画面:

- users
- effects
- referral_codes
- settlements
- settlement_exports

---

## 7. 認証導線

主な画面:

- devise/sessions
- devise/passwords
- phone_sessions
- phone_verifications
- customers/registrations
- casts/registrations
- store_admins/registrations
- stores/registrations
- email_changes

電話番号OTP、Devise、招待登録、メール変更が分かれている。

---

## 8. モーダル設計

modal_controller と Turbo Frame を組み合わせる。

用途:

- ブース入室選択
- 店舗選択
- ブース選択

Turbo Frame load をきっかけに Bootstrap Modal を開く。

---

## 9. Onboarding

onboarding_controller は店舗導入後の行動を促す。

想定ステップ:

- キャスト招待
- 招待URL作成
- ダッシュボードへ戻る
- ドリンク設定

対象要素に highlight を当て、Popover を表示する。

---

## 10. UI設計上の注意点

- fixed subnav と header dropdown の重なりに注意する
- live画面はモバイルキーボード表示時の高さ調整が必要
- お気に入りボタンは同一対象が複数表示されるため同期が必要
- LPやlegalは未ログインでもアクセスされる前提で設計する
