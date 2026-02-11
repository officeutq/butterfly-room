# Butterflyve（Butterfly Room）

店舗単位で成立するライブ配信 × 売上確定プラットフォーム。

> 「配信」ではなく、「売上が成立する配信」をつくる。

---

## Philosophy

売上の整合性を最優先に設計する。  
柔軟性よりも安全性を優先する。  
履歴を壊さない。

---

## 🦋 概要

Butterflyve は、夜の店文化を前提とした  
「店舗単位で売上を成立させる」ライブ配信サービスです。

顧客は配信を視聴し、ドリンク（ポイント商品）を送信できます。  
キャストがドリンクを「消化」した瞬間に売上が確定し、  
配信終了時に未消化分は自動返却されます。

売上の正は台帳（ledger）とし、  
整合性を最優先で設計しています。

---

## 🎯 Phase1 コンセプト

Phase1では柔軟性よりも「整合性と安全性」を優先します。

- 売上は消化確定分のみ
- 返却は売上に含めない
- 1ブース1キャスト
- ブース紐づけ変更不可
- ブースは論理削除（archived_at）

---

## 🚀 主要機能（Phase1）

### 店舗

- ブース作成／管理／アーカイブ
- キャスト招待（本人承認必須）
- ブースへのキャスト紐づけ（確定後変更不可）
- 売上確認（台帳ベース）

### キャスト

- 配信開始／席外し／復帰／終了
- ドリンク消化（売上確定）

### 顧客

- 視聴（Presence）
- コメント投稿
- ポイント購入（Stripe）
- ドリンク送信

---

## 🏗 技術スタック

- Ruby on Rails 8
- Hotwire（Turbo）
- PostgreSQL
- Amazon IVS Real-Time（Stage）
- Stripe（Checkout + Webhook）
- Docker Compose
- Amazon IVS Real-Time（Stage）
- AWS（EC2 / RDS / CloudFront）

---

## 📚 設計ドキュメント

設計思想と仕様はすべて `docs/` に整理されています。

- [企画書](docs/01_Butterfly%20Room（仮）企画書.md)
- [要件定義書](docs/02_要件定義書.md)
- [基本設計_Phase1](docs/03_基本設計_Phase1.md)
- [Rails設計](docs/04_Rails設計.md)
- [WebRTC_配信シグナリング設計](docs/05_WebRTC_配信シグナリング設計.md)
- [配信映像設計](docs/06_配信映像設計.md)

---

## 🧪 開発環境セットアップ

### 必要要件

- Docker
- Docker Compose

### 初回セットアップ

```bash
docker compose build
docker compose run --rm app bin/rails db:prepare
docker compose up
```

アクセス：

```
http://localhost:3000
```

---

## 🛠 開発コマンド

```bash
# console
docker compose run --rm app bin/rails console

# migrate
docker compose run --rm app bin/rails db:migrate

# test
docker compose run --rm app bin/rails test
```

---

## 🔐 環境変数（主要）

* DATABASE_URL
* SECRET_KEY_BASE
* STRIPE_SECRET_KEY
* STRIPE_WEBHOOK_SECRET
* AWS_REGION
* AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY（またはInstance Profile）

詳細は `.env.example` を参照。

---

## 🧾 売上設計ポリシー

* 売上の正は `store_ledger_entries`
* 二重計上不可（drink_order_id unique）
* 消化確定のみ売上
* 未消化は返却

整合性を最優先に設計しています。

---

## 📈 Phase2以降（構想）

* 店舗／キャストランキング
* 期間切替（週／月／イベント）
* イベントランキングのリアルタイム更新
* ブース切替可能化（cast_user_id保持）
* 店舗対決機能

---

## 📄 ライセンス

Private
