# 基本設計（Phase 1 / MVP）

## 0. 設計方針

* **状態は少なく**：配信状態は `offline / live / away` の3つ
* **決済は外部**：ポイント購入は外部決済、アプリは台帳管理に専念
* **売上確定は“消化”**：送信時は保留、キャスト消化で確定
* **モデレーションは店舗**：運営介入は最小、ログは残す

---

## 1. 画面遷移図（ロール別）

### 1.1 顧客（Customer）

**目的**：配信を見る → ドリンク送る → ポイント足りなければ買う

```
[トップ]
  ├─(タップ)→ [ブース視聴]
  │             ├─(送信)→ ドリンク送信（ボトムシート）
  │             ├─(残高不足)→ [ポイント購入] → (購入完了) → [ブース視聴]へ戻る
  │             └─(戻る)→ [トップ]
  └─(任意)→ [ポイント購入]
```

**トップ表示（MVP）**

* 配信中のお気に入り（Phase2で本格化でもOK）
* 配信中のレア配信（Phase2が本命、MVPは枠だけでも可）
* 配信中（新着順）

---

### 1.2 キャスト（Cast）

**目的**：配信開始 → コメント確認 → 未消化消化 → 席外し → 復帰 → 終了

```
[ブース選択/バックヤード]
  ├─(配信開始)→ [配信バックヤード（live/away操作 + 消化 + コメント）]
  │                ├─(席外しON/OFF)→ 状態切替
  │                ├─(未消化先頭をタップ)→ 消化処理
  │                └─(配信終了)→ 終了処理（未消化返却）→ [ブース選択/バックヤード]
  └─(プロフィール編集)→ [プロフィール編集]
```

**プレビュー挙動（確定仕様）**

* 配信開始時入室0 → 拡大プレビュー
* 入室1以上になった瞬間 → 自動で縮小プレビュー（左上）
* 縮小プレビュー長押し → 拡大
* 拡大プレビュー長押し → 縮小

---

### 1.3 店舗管理者（Store Admin）

**目的**：メニュー設定／キャスト数値閲覧／モデレーション

```
[管理トップ]
  ├─→ [ドリンクメニュー管理]
  ├─→ [ブース管理（基本）]
  ├─→ [キャスト別数値一覧]
  └─→ [モデレーション（店舗BAN/削除）]
```

---

## 2. 配信セッションと入室者数（技術設計）

### 2.1 基本概念

* **Booth（ブース）**：店舗に所属する配信単位
* **StreamSession（配信セッション）**：ブースの1回の配信（開始〜終了）
* **Presence（入室/滞在）**：顧客がセッションに入室している状態（同接算出）

### 2.2 状態モデル

* Boothには `status: offline / live / away`
* StreamSessionには `started_at / ended_at / status`（実体としては `live/ended` でもOK）

**開始**

* キャストが配信開始 → Booth.status = `live`
* **同時に StreamSession を1件生成**（ended_at=nil）

**席外し**

* Booth.status = `away`
* セッションは継続（StreamSession は継続）

**終了**

* Booth.status = `offline`
* StreamSession.ended_at をセット
* 未消化ドリンクを一括返却

### 2.3 同接（入室者数）の算出

MVPで安定する実装は **Presence（滞在）を持つ** 方式です。

**Presenceテーブル（例）**

* stream_session_id
* customer_id
* joined_at
* last_seen_at
* left_at（nullなら滞在中）

**同接数の計算**

* `left_at IS NULL` かつ `last_seen_at が一定時間以内`（例：60秒以内）
* これを COUNT したものを同接として表示

**last_seen_at 更新**

* 視聴画面が開いている間、クライアントが定期的に ping（例：20〜30秒）して更新
* 閉じたら left_at を即時更新（できなければタイムアウトで自然離脱）

> MVPでは「正確すぎる同接」より「破綻しない同接」が大事です。

---

了解。では基本設計の続きとして、**状態遷移図（Phase1）**を「仕様としてそのまま書ける」形でまとめます。
（図は文章＋表で表現。あとでMermaid化も可能）

---

## 3. 状態遷移

### 3.1. 配信状態（Booth / StreamSession）

#### 3.1.1 状態一覧

| 状態        | 画面表示           | 意味          | 課金       |
| --------- | -------------- | ----------- | -------- |
| `offline` | 配信は終了しました／次回予定 | 配信セッションなし   | ❌        |
| `live`    | 配信中            | 配信セッション稼働   | ⭕        |
| `away`    | 席外し中           | セッション継続（離席） | ⭕（MVPは可） |

#### 3.1.2 状態遷移

```
offline → live → away → live → offline
                 ↘︎         ↗︎
                   → offline
```

#### 3.1.3 遷移トリガー（誰が何をするか）

| トリガー   | 実行者  | 事前条件             | 結果                          |
| ------ | ---- | ---------------- | --------------------------- |
| 配信開始   | キャスト | `offline`        | `live` + StreamSession生成    |
| 席外しON  | キャスト | `live`           | `away`（セッション継続）             |
| 席外しOFF | キャスト | `away`           | `live`                      |
| 配信終了   | キャスト | `live` or `away` | `offline` + セッション終了 + 未消化返却 |

#### 3.1.4 配信終了時の必須処理（重要）

配信終了（`live/away → offline`）の同一トランザクションで以下を行う：

* StreamSession の `ended_at` 設定
* 未消化ドリンク（`pending`）を全件 `refunded` に更新
* 顧客Walletの `reserved → available` を返却（整合性優先）

---

### 3.2. 入室（Presence）状態と同接

#### 3.2.1 Presence状態

Presenceは「その配信セッションに顧客が滞在しているか」を表す。

| 状態       | 条件                                                 |
| -------- | -------------------------------------------------- |
| 滞在中      | `left_at IS NULL` かつ `last_seen_at` が閾値以内          |
| 離脱済      | `left_at IS NOT NULL`                              |
| タイムアウト離脱 | `left_at IS NULL` だが `last_seen_at` が閾値外（集計上は離脱扱い） |

#### 3.2.2 同接数算出（MVP仕様）

* 同接 = 「滞在中」PresenceのCOUNT
* `last_seen_at` 更新はクライアントの定期pingで行う
* 閾値は基本設計で仮置き（例：60秒）

---

### 3.3. ドリンク注文（DrinkOrder）状態遷移

#### 3.3.1 状態一覧

| 状態         | 意味      | 顧客ポイント             | 店舗売上 |
| ---------- | ------- | ------------------ | ---- |
| `pending`  | 未消化（保留） | reservedに積まれている    | 未計上  |
| `consumed` | 消化済（確定） | reservedから減る       | 加算   |
| `refunded` | 返却済     | reserved→available | なし   |

#### 3.3.2 状態遷移図

```
pending → consumed
   ↓
refunded
```

#### 3.3.3 遷移トリガー

| トリガー   | 実行者  | 条件                                                  | 結果                         |
| ------ | ---- | --------------------------------------------------- | -------------------------- |
| ドリンク送信 | 顧客   | 残高available >= price / BANなし / booth `live or away` | `pending` 作成 + Wallet hold |
| ドリンク消化 | キャスト | `pending` かつ FIFO先頭                                 | `consumed` + 店舗売上加算        |
| 未消化返却  | システム | セッション終了                                             | `pending → refunded`（一括）   |

---

### 3.4. Wallet（ポイント）状態遷移（MVP）

#### 3.4.1 Walletの保持値（推奨）

* `available_points`：使える残高
* `reserved_points`：未消化ドリンクとして保留中の残高

#### 3.4.2 操作別の増減

| 操作              | available | reserved | 備考             |
| --------------- | --------: | -------: | -------------- |
| ポイント購入          |         + |        0 | 購入成功確定後に反映     |
| ドリンク送信（hold）    |    -price |   +price | `pending` と同期  |
| ドリンク消化（consume） |         0 |   -price | 代わりに店舗売上へ      |
| 未消化返却（release）  |    +price |   -price | `refunded` と同期 |

#### 3.4.3 不整合防止の要件

* `reserved_points` は `pending` 合計と一致すること（監査・修復の基準）
* `available_points` が負にならないこと（DB制約 or サーバ検証）

---

### 3.5. 店舗売上（StoreLedger）状態

#### 3.5.1 店舗売上に計上される条件

* `DrinkOrder.status == consumed` になった時点で、店舗売上ポイントを加算する

#### 3.5.2 取引の追跡要件

* 店舗管理画面で見える「配信売上」は以下で追跡可能とする：

  * consumed drink_orders の合計
  * store_ledger_entries の合計（どちらかを正とする）

MVPでは「集計しやすい方」を正にして、もう片方は監査補助でもOK。

---

### 3.6. 例外系（Phase1の最低限仕様）

#### 3.6.1 二重送信対策

* 顧客側：送信ボタン連打抑止
* サーバ側：同一リクエスト重複を弾ける仕組み（idempotency key推奨）

#### 3.6.2 FIFO消化の保証（必須）

* キャスト消化は必ず「先頭のみ」
  ⇒ DBトランザクション＋行ロックで担保する（基本設計要件）

#### 3.6.3 BAN時の動作

* BANされた顧客は

  * 入室不可（ブース表示前にブロック）
  * ドリンク送信不可（再チェック）
  * コメント不可（再チェック）

---

了解。では続けて、**Phase 1 / MVPのDB設計（確定版）**を「そのまま実装に落とせる粒度」でまとめます。
（※“正”となるデータの持ち方・整合性・インデックス・代表クエリまで含めます）

---

## 4. Phase 1 DB設計

### 4.0. 設計の前提（このDBで守ること）

* **配信は StreamSession が正**（「いつからいつまで配信したか」を確実に残す）
* **未消化（pending）の合計が reserved_points と一致**できる構造
* **消化（consumed）は必ずFIFO（先頭のみ）**
* 配信終了時は **pending→refunded の一括返却**が必ずできる

---

### 4.1. テーブル一覧（Phase1）

#### 認証・ロール

* `users`
* （必要なら）`profiles`（cast/customerの拡張。Phase1はusersに寄せてもOK）

#### 店舗・所属

* `stores`
* `store_memberships`（キャスト/管理者の所属）

#### ブース・配信

* `booths`
* `booth_casts`
* `stream_sessions`
* `presences`（同接/入室管理）

#### 課金・ポイント

* `wallets`
* `wallet_transactions`（監査用台帳：MVPでも推奨）
* `drink_items`
* `drink_orders`
* `store_ledger_entries`（店舗売上台帳：MVPでも推奨）

#### モデレーション

* `store_bans`

#### コメント

* `comments`

---

### 4.2. 各テーブル定義（主キー/外部キー/制約）

#### 4.2.1 users

**目的**：ロールを一元管理

* id (PK)
* role（enum）

  * `customer` / `cast` / `store_admin` / `system_admin`
* display_name
* （認証情報：採用方式に依存）

**制約**

* role は必須

**インデックス**

* role（任意：管理画面の絞り込み用）

---

#### 4.2.2 stores

* id (PK)
* name
* …（住所などはPhase2でもOK）

---

#### 4.2.3 store_memberships

**目的**：ユーザーの店舗所属（キャスト複数店舗可／管理者も店舗所属）

* id (PK)
* store_id (FK → stores)
* user_id (FK → users)
* membership_role（enum）

  * `cast` / `admin`

**制約**

* unique(store_id, user_id, membership_role)
  ※「同じ店舗で同じ役割を二重登録」防止
  （役割を1列にまとめるなら unique(store_id, user_id) でも可）

**インデックス**

* (store_id, membership_role)
* (user_id)

---

#### 4.2.4 booths

**目的**：店舗の配信単位

* id (PK)
* store_id (FK)
* name
* status（enum：offline/live/away）
* current_stream_session_id（nullable, FK → stream_sessions）

**制約**

* status 必須
* store_id 必須

**インデックス**

* (store_id, status)
* current_stream_session_id（任意）

> `current_stream_session_id` は「今の配信セッション」を辿るためのショートカット。
> 正は stream_sessions で、整合性はアプリ側で担保します（開始時にセット、終了時にnull）。

---

#### 4.2.5 booth_casts

**目的**：ブースに参加するキャスト紐付け

* id (PK)
* booth_id (FK → booths)
* cast_user_id (FK → users)

**制約**

* unique(booth_id, cast_user_id)

**インデックス**

* (booth_id)
* (cast_user_id)

---

#### 4.2.6 stream_sessions

**目的**：配信の開始〜終了を確定記録（集計の正）

* id (PK)
* booth_id (FK)
* store_id (FK) ※冗長だが集計高速化に有効
* status（enum：live/ended）※ ended_at だけでも代用可
* started_at
* ended_at（nullable）
* started_by_cast_user_id (FK → users)

**制約**

* started_at 必須
* booth_id 必須

**インデックス**

* (booth_id, started_at desc)
* (store_id, started_at desc)
* (ended_at)（任意）

**整合性要件（アプリ側）**

* booth.status != offline の時は current_stream_session_id が存在すること

---

#### 4.2.7 presences

**目的**：同接算出・入室状態（last_seenでタイムアウト）

* id (PK)
* stream_session_id (FK)
* customer_user_id (FK → users)
* joined_at
* last_seen_at
* left_at（nullable）

**制約**

* joined_at 必須
* last_seen_at 必須

**インデックス（必須）**

* (stream_session_id, left_at)
* (stream_session_id, last_seen_at)
* unique(stream_session_id, customer_user_id, joined_at)（任意：入室ログを残したい場合）

**同接算出の前提**

* “滞在中”は
  `left_at is null AND last_seen_at >= now - threshold` を満たすもの

---

### 4.3. 課金・売上テーブル

#### 4.3.1 wallets

**目的**：顧客のポイント残高（available/reserved）

* id (PK)
* customer_user_id (FK → users)
* available_points（integer）
* reserved_points（integer）
* created_at / updated_at

**制約**

* unique(customer_user_id)
* available_points >= 0
* reserved_points >= 0

**インデックス**

* (customer_user_id)

---

#### 4.3.2 wallet_transactions（推奨）

**目的**：監査・修復・問い合わせ対応のための台帳

* id (PK)
* wallet_id (FK → wallets)
* kind（enum）

  * purchase / hold / release / consume / adjustment（MVPでも adjustment はあると便利）
* points（signed int：増減）
* ref_type / ref_id（drink_order や決済IDの参照）
* occurred_at

**制約**

* occurred_at 必須

**インデックス**

* (wallet_id, occurred_at desc)
* (ref_type, ref_id)

> Walletの数値だけ持つと「なぜこうなった？」が追えません。
> MVPでも台帳は入れておくと運用が劇的に楽になります。

---

#### 4.3.3 drink_items

**目的**：店舗が設定するドリンク商品

* id (PK)
* store_id (FK)
* name
* price_points（integer）
* position（integer）
* enabled（boolean）

**制約**

* price_points > 0
* enabled 必須

**インデックス**

* (store_id, enabled, position)

---

#### 4.3.4 drink_orders（最重要）

**目的**：送信→未消化→消化/返却

* id (PK)
* store_id (FK)
* booth_id (FK)
* stream_session_id (FK)
* customer_user_id (FK → users)
* drink_item_id (FK)
* status（enum：pending/consumed/refunded）
* created_at
* consumed_at（nullable）
* refunded_at（nullable）

**制約**

* status 必須
* store_id / booth_id / stream_session_id 必須
* `consumed_at` は consumed時に必須（アプリ側）
* `refunded_at` は refunded時に必須（アプリ側）

**インデックス（必須）**

* FIFO用：`(stream_session_id, status, created_at, id)`
  → 先頭pending検索が速い
* 顧客履歴：`(customer_user_id, created_at desc)`
* 店舗集計：`(store_id, status, created_at)` / `(store_id, consumed_at)`

**整合性要件**

* 消化は必ず先頭pendingのみ（DBロック＋トランザクションで担保）

---

#### 4.3.5 store_ledger_entries（推奨）

**目的**：店舗売上ポイントの確定台帳（手数料計算の元）

* id (PK)
* store_id (FK)
* stream_session_id (FK)
* drink_order_id (FK)
* points（integer）
* occurred_at

**制約**

* points > 0
* unique(drink_order_id)（同一注文を二重計上しない）

**インデックス**

* (store_id, occurred_at desc)
* (stream_session_id)

> `consumed` の合計だけでも売上は出せますが、
> “正規の売上台帳”があると「振込」「手数料控除」へ繋げやすいです（Phase2で効く）。

---

### 4.4. モデレーション・コメント

#### 4.4.1 store_bans

* id (PK)
* store_id (FK)
* customer_user_id (FK)
* reason
* created_by_store_admin_user_id (FK → users)
* created_at

**制約**

* unique(store_id, customer_user_id)（同一店舗で重複BAN防止）

**インデックス**

* (store_id)
* (customer_user_id)

---

#### 4.4.2 comments

* id (PK)
* stream_session_id (FK)
* booth_id (FK)
* user_id (FK → users)
* body
* created_at
* deleted_at（nullable：店舗削除用）

**インデックス**

* (stream_session_id, created_at)
* (booth_id, created_at)

---

### 4.5. 必須インデックスまとめ（実装チェックリスト）

* presences: `(stream_session_id, left_at)`, `(stream_session_id, last_seen_at)`
* drink_orders: `(stream_session_id, status, created_at, id)`（FIFO）
* store_bans: `unique(store_id, customer_user_id)`
* store_memberships: `(store_id, membership_role)` / `unique(...)`
* wallets: `unique(customer_user_id)`
* store_ledger_entries: `unique(drink_order_id)`

---

### 4.6. 代表クエリ（設計確認用）

#### 4.6.1 同接数（MVP）

* 対象セッションの presences で

  * left_at is null
  * last_seen_at が閾値以内
    を数える

#### 4.6.2 未消化先頭取得（FIFO）

* `stream_session_id = ? AND status = 'pending'`
* `created_at asc, id asc`
* 先頭1件

#### 4.6.3 消化処理（先頭保証）

* 先頭pendingを **行ロック**して更新（同時消化を防ぐ）
* 更新成功したら store_ledger_entries を作る

#### 4.6.4 配信終了時の一括返却

* `stream_session_id = ? AND status='pending'` を refunded へ更新
* 更新した件数・合計ポイントを使って wallet.reserved→available を調整
  （本当は「注文ごと」に返却が理想だが、MVPは合計でも成立）

---

### 4.7. トランザクション境界（重要）

MVPでも以下は必ず **DBトランザクション**でまとめます。

#### 4.7.1 ドリンク送信

* BAN/残高チェック
* walletの available/reserved 更新
* drink_orders 作成
* wallet_transactions 作成（採用する場合）

#### 4.7.2 ドリンク消化（FIFO）

* 先頭pendingのロック
* drink_orders → consumed
* wallet.reserved 減
* store_ledger_entries 作成
* wallet_transactions 作成

#### 4.7.3 配信終了（返却）

* stream_sessions 終了
* booth offline化
* pending→refunded一括更新
* wallet reserved→available返却（合計）
* wallet_transactions 作成

---

### 4.8. Phase2へ繋がる拡張余地（DBは壊さない）

この設計のまま、Phase2で自然に足せます：

* `payouts`（店舗振込管理）
* `events/reservations`（レア配信、予約）
* `favorites/notifications`
* `audit_logs`（管理操作ログ強化）

---

## 5. 主要ユースケース別シーケンス

### 5.1 顧客がドリンク送信

1. 顧客がブース視聴中（セッション参加中）
2. ドリンクタップ
3. サーバ：BANチェック → 残高チェック（available >= price）
4. Wallet: available↓ reserved↑（hold）
5. DrinkOrder: pending 作成
6. UI：演出、コメント欄に「送信」表示

### 5.2 キャストがドリンク消化（FIFO）

1. キャスト画面で未消化先頭のみ有効
2. タップ
3. サーバ：該当注文が `pending` かつ先頭であること検証
4. DrinkOrder: consumed
5. Wallet: reserved↓（consume）
6. StoreLedgerEntry: +points
7. UI：演出、次の注文が先頭になる

### 5.3 配信終了 → 未消化返却

1. キャストが配信終了
2. Booth.status=offline、StreamSession.ended_at 設定
3. pending の drink_orders を全て refunded に更新
4. Wallet: reserved→available（release）
5. 顧客UI：必要なら「返却されました」通知（MVPはなくてもOK）

---

## 6. Phase 1 画面別の表示要件（抜粋）

### 顧客：ブース視聴

* 映像フルスクリーン＋オーバーレイ
* 右側アクション：残高／ドリンクボタン
* ドリンクはボトムシート
* コメントは下部オーバーレイ

### キャスト：バックヤード

* 上部：状態・同接・売上pt・経過
* 中央：配信映像
* 右：未消化キュー（先頭のみ有効）
* 下：コメント流れる
* プレビュー：入室0なら拡大、入室>0で縮小、長押しで拡大

### 店舗管理：数値一覧

* キャスト別に

  * 配信売上（store ledger集計）
  * 配信時間（stream_sessions集計）
  * 配信売上/時間（算出）
  * 実店舗売上（入力値）

---

## 7. 非機能・安全設計（MVP必須だけ）

* **冪等性**：ドリンク送信は二重送信防止（クライアント側ボタン連打対策 + サーバ側idempotency key推奨）
* **整合性**：消化は「先頭のみ」をDBレベルで守る（トランザクション + 行ロック）
* **監査**：wallet_transactions と drink_orders と store_ledger の3点で追えるようにする
* **BAN**：入室時とドリンク送信時に必ずBANチェック

---

## 8. 決済方式の選定

ポイント購入の決済方式として、Phase 1では Stripe を採用する。
Stripeを通じてクレジットカードおよび Apple Pay / Google Pay に対応する。

アプリ内での課金行為はすべてポイント消費として扱い、
外部決済はポイント購入時にのみ行う。

Apple App Store / Google Play のアプリ内課金は Phase 1 では採用しない。



このサービスは、

* UI
* 配信体験
* ドリンクの気持ちよさ

が勝負です。

**決済は「邪魔をしない存在」であるべき**で、
Stripe + Wallet設計はその条件を満たしています。

---

### 8.1 Webアプリ（Phase1）

* **同一タブで決済画面へ遷移**
* 決済完了後は `return_url` で **元のブースへ復帰**
* 復帰後に

  * 残高を再取得して表示更新
  * 必要ならドリンク送信パネルを自動再表示

---

### 8.2 具体的なユーザー体験（MVP確定）

1. ブースでドリンクを押す
2. 残高不足 → 「ポイント購入」モーダル（購入パック選択）
3. 購入を押す → 決済画面へ遷移（同一タブ）
4. 決済成功 → 自動でブースに戻る（return_url）
5. 残高が増えている → そのままドリンク送信

キャンセル/失敗でも同じようにブースへ戻す（状態表示だけ変える）

---

### 8.3 決めておくと事故が減る2点

#### 8.3.1 戻り先パラメータ

* `return_url` に最低限入れる

  * `booth_id`
  * `checkout_status`（success/cancel/failed）
  * `pack_id`（任意）
  * `drink_item_id`（任意：送ろうとしてた商品）

#### 8.3.2 復帰後の挙動

* `success`：残高更新 → ドリンクパネル再表示（任意）
* `cancel/failed`：残高更新せず → 購入モーダルを再表示するか、トーストで案内

---

## 9. リアルタイム設計（Phase1）

### 9.0. 採用方針（確定）

* **コメント**：Turbo Streams（ActionCable）でリアルタイム
* **ドリンク（送信/消化/返却）通知**：Turbo Streamsでリアルタイム
* **同接数**：ポーリング（10〜30秒間隔）
* **Presence（入室記録）**：Phase1はDB（presences）でOK。将来Redis差し替え可能な形にする

---

### 9.1. チャンネル設計（ブース単位）

#### 9.1.1 チャンネル（ストリーム）の単位

Phase1は **StreamSession単位（配信1回）** を基本にします。

* コメントは「その配信回」に紐づくのが自然
* 配信終了時に切り替え/クリーンにしやすい
* 返却通知もセッション単位にまとめやすい

##### ストリーム名（概念）

* `stream_session:{id}:comments`
* `stream_session:{id}:events`

※実装ではTurbo Streamsの `turbo_stream_from` を使い、セッションIDで購読する。

---

#### 9.1.2 画面別の購読

##### 顧客：ブース視聴画面

購読するもの

* コメントストリーム（新規コメントがappendされる）
* イベントストリーム（ドリンク送信演出、席外し/終了通知など）

##### キャスト：配信バックヤード

購読するもの

* コメントストリーム（顧客コメント）
* イベントストリーム（ドリンク到着、消化反映、返却反映）
* 未消化キュー更新（消化成功で先頭が変わる）

##### 店舗管理者

* Phase1ではリアルタイム不要（一覧更新はリロードでOK）

---

### 9.2. イベント種別（ドリンク/状態通知）

#### 9.2.1 eventsストリームで流すもの（Phase1）

イベントは「UIを更新するための通知」に限定します。

##### 顧客向けイベント

* 自分の送信成功（即時反映はローカルでも可）
* 配信状態変更（live/away/offline）
* 配信終了と返却（pendingがrefundedになった時）

##### キャスト向けイベント

* 新規ドリンク到着（pending追加）
* ドリンク消化成功（pending→consumed、先頭移動）
* 配信終了処理（未消化返却が走ったこと）

---

#### 9.2.2 Turbo Streamsの操作（基本）

* コメント：`append`（コメント一覧の末尾に追加）
* 未消化キュー：`replace`（右カラム全体を差し替え）
* ステータスバー（売上・経過）：`replace`（必要なら）

> MVPで一番安定するのは「細かく部分更新しすぎない」こと。
> 未消化はカラムごとreplaceで十分です。

---

### 9.3. コメント設計（ActionCable）

#### 9.3.1 送信フロー

1. 顧客がコメント送信（HTTP POST）
2. サーバで保存（comments）
3. 保存成功したら `stream_session:{id}:comments` に Turbo Stream で `append`
4. 視聴者/キャスト双方で即表示

#### 9.3.2 制限（Phase1）

* 文字数上限（例：200）
* 連投制限（例：1秒に1回まで）
* BANユーザーは送信不可

（連投制限はrack-attack等でも良い）

---

### 9.4. ドリンク通知設計（ActionCable）

#### 9.4.1 顧客がドリンク送信（pending作成）

処理（DBトランザクション）

* BAN/残高チェック
* wallet hold（available↓ reserved↑）
* drink_order(pending) 作成
* wallet_transactions 記録（採用する場合）

通知（Turbo Streams）

* キャスト向け：未消化キュー更新（`replace`）
* 顧客向け：送信完了演出（`append` or `replace` で軽く）

> 顧客側は「自分が押した結果」なので、まずローカルで演出してOK
> ただし確定のためにサーバ応答に合わせる（失敗時は戻す）

---

#### 9.4.2 キャストが消化（consumed）

処理（DBトランザクション）

* 先頭pendingをロックして検証（FIFO保証）
* consumedへ更新、consumed_at
* wallet reserved 減算
* store_ledger_entries 加算
* wallet_transactions 記録

通知（Turbo Streams）

* キャスト向け：未消化キュー更新（replace）
* 顧客向け：イベント（「消化された」表示はPhase1は任意。自分視点の安心用に入れても良い）

> “消化された”を顧客に出すなら、コメント欄に「○○が乾杯しました」程度が良い（過剰に業務っぽくしない）

---

#### 9.4.3 配信終了（未消化返却）

処理（DBトランザクション）

* stream_session終了
* booth offline化
* pending→refunded 一括更新
* wallet reserved→available 返却

通知（Turbo Streams）

* 顧客向け：配信終了カードへ `replace`
* 顧客向け：返却通知（トースト/メッセージ）
* キャスト向け：配信終了反映（右カラムをクリア）

---

### 9.5. 同接（Presence）ポーリング設計

#### 9.5.1 更新頻度（Phase1推奨）

* 顧客視聴画面：**20〜30秒**ごとに同接表示更新
* キャスト画面：**10〜20秒**ごとに同接表示更新
  （キャストは気にするので少し短め）

#### 9.5.2 エンドポイント（概念）

* `GET /stream_sessions/:id/presence_summary`

  * returns: `{ viewer_count: 128 }`

#### 9.5.3 Presenceの更新（ping）

視聴中、クライアントが定期的に

* `POST /stream_sessions/:id/presences/ping`

サーバは

* 既存presenceがあれば last_seen_at 更新
* なければ joined_at作成

離脱は

* `beforeunload`で left_at 更新を試みる（成功すれば良い）
* 最終的には last_seen_at タイムアウトで離脱扱い

> Phase1は「厳密」より「破綻しない」が最優先。

---

### 9.6. 実装の境界（重要：どこまでCableでやるか）

#### Cable（Turbo Streams）でやる

* コメント追加
* ドリンク到着/消化で未消化キュー更新
* 配信終了/席外しなどの状態通知

#### HTTP + ポーリングでやる

* 同接表示
* 残高取得（購入復帰後の再取得もここ）
* 初期ロード（画面表示時の初期データ）

---

### 9.7. 成長したら差し替えるポイント

#### 9.7.1 PresenceをRedisへ

* Phase1: DB presences
* Phase2+: Redisで

  * `SET` / `ZSET`（last_seen）管理
  * viewer_countの高速算出

アプリ側は “PresenceService” のように抽象化して、実装を差し替え可能にする。

#### 9.7.2 Cableの分離

* アプリサーバとCableサーバを分離（スケール）
* Redisをpubsubにする

---

### 9.8. Phase1 Done（リアルタイム観点）

* コメントがリアルタイムに流れる
* ドリンク送信/消化でキャスト側の未消化キューが即更新される
* 配信終了で視聴画面が終了状態に切り替わり、未消化が返却される
* 同接表示はポーリングで更新される（多少ズレても良い）

---

## 10. Phase1 API設計（一覧＋リクエスト/レスポンス）

**Phase1 API設計（エンドポイント一覧＋権限＋主要I/O＋エラー仕様）** を基本設計としてまとめます。
※URLは例。実装で多少変えてOKですが、**粒度と責務**はこのままが安定します。

---

### 10.0. 共通方針

* 認証必須（顧客/キャスト/店舗管理者）
* すべての変更系（POST/PATCH）は **権限チェック**＋**状態チェック**を行う
* 変更系は **トランザクション**で整合性を守る
* リアルタイム通知は Turbo Streams（ActionCable）で配信し、APIは状態の確定に専念する

---

### 10.1. 顧客（Customer）向け

#### 10.1.1 トップ表示

##### GET /home_feed

**権限**：customer
**目的**：配信中一覧（MVP）

**レスポンス例**

* 配信中ブース（新着順）
* （任意）お気に入り配信中（Phase2で強化）
* （任意）レア配信枠（Phase2で強化）

---

#### 10.1.2 ブース視聴（初期データ）

##### GET /booths/:booth_id

**権限**：customer（ログイン必須にするかは方針次第。MVPは必須推奨）
**目的**：ブース視聴画面の初期表示に必要なデータを返す

返すべき最小データ

* booth: id, name, status
* current_stream_session_id（live/away時）
* viewer_count（presence summary）
* wallet_balance（available/reserved）
* drink_items（enabled + position）
* latest_comments（直近N件、例：30件）
* ban_status（trueならここで弾く）

---

#### 10.1.3 Presence（入室/滞在 ping）

##### POST /stream_sessions/:id/presences/ping

**権限**：customer
**目的**：joined_at作成 or last_seen更新

**リクエスト**

* bodyなしでOK（認証ユーザーで判定）
* 任意：client_ts

**レスポンス**

* 200 OK
* viewer_count（返しても良い：表示更新に使える）

**エラー**

* 403 banned
* 404 session not found
* 409 session ended（終了済）

---

#### 10.1.4 同接取得（ポーリング）

##### GET /stream_sessions/:id/presence_summary

**権限**：customer / cast
**レスポンス**

* viewer_count

---

#### 10.1.5 コメント送信

##### POST /stream_sessions/:id/comments

**権限**：customer
**目的**：コメント投稿 → Turbo Streamsで配信

**リクエスト**

* body: { text }

**成功**

* 201 created（または200）
* comment_id

**通知（Turbo Streams）**

* `stream_session:{id}:comments` に append

**エラー**

* 403 banned
* 422 validation（空、文字数超過）
* 429 rate limit（連投）
* 409 session ended

---

#### 10.1.6 ドリンク送信（購入＝pending作成）

##### POST /stream_sessions/:id/drink_orders

**権限**：customer
**目的**：wallet hold + drink_order(pending)

**リクエスト**

* drink_item_id

**成功レスポンス**

* drink_order_id
* new_wallet: available_points, reserved_points

**通知（Turbo Streams）**

* キャスト：未消化キュー replace
* 顧客：送信演出（任意）

**エラー**

* 403 banned
* 409 session ended / booth offline
* 409 booth not live/away（offline）
* 402 insufficient_points（available不足）
* 422 item invalid（店舗のitemでない/無効）

---

### 10.2. ポイント購入（決済）

#### 10.2.1 購入開始（Checkout生成）

##### POST /wallet/purchases

**権限**：customer
**目的**：Stripe Checkout Session等を作り、決済URLを返す

**リクエスト**

* pack_id（例：1000/3000/5000/10000）
* context（任意）

  * booth_id（ブースからの購入なら必須推奨）
  * stream_session_id（任意）
  * drink_item_id（任意）

**成功**

* checkout_url（同一タブで遷移）
* return_url（内部的に保持でも可）

**エラー**

* 422 pack invalid

---

#### 10.2.2 決済完了復帰（return_url）

##### GET /checkout/return?status=success|cancel|failed&booth_id=...&stream_session_id=...&drink_item_id=...

**権限**：customer
**目的**：復帰後の画面制御

* success：wallet再取得 →（任意）ドリンクパネル再表示
* cancel/failed：案内を表示 → ブースへ戻す

> walletの増加反映はWebhookが正。復帰時点で未反映なら「反映中」表示して数秒後に再取得する設計が堅い。

---

### 10.3. キャスト（Cast）向け

#### 10.3.1 キャストのブース一覧（所属ブース）

##### GET /cast/booths

**権限**：cast
**目的**：自分が入れるブース一覧

---

#### 10.3.2 配信開始

##### POST /cast/booths/:booth_id/stream_sessions

**権限**：cast（そのboothに紐づくキャストであること）
**目的**：booth live化 + stream_session作成 + current_stream_session_idセット

**成功**

* stream_session_id
* booth_status=live

**通知（Turbo Streams）**

* 顧客側：booth status更新（必要なら）

**エラー**

* 403 not_member
* 409 already_live（既に配信中）
* 409 booth locked（同時開始競合）

---

#### 10.3.3 席外しON/OFF

##### PATCH /cast/booths/:booth_id/status

**権限**：cast
**リクエスト**

* status: away or live

**条件**

* current_stream_session_id が存在
* booth.status が live/away の範囲

**通知**

* 視聴側に席外し状態を通知（eventsで replace）

---

#### 10.3.4 配信終了

##### POST /cast/stream_sessions/:id/end

**権限**：cast（該当セッションの開始キャスト or booth所属キャスト）
**目的**：セッション終了 + pending返却 + booth offline化

**成功**

* ended_at
* refunded_count
* refunded_points_sum

**通知（Turbo Streams）**

* 顧客：終了カード表示（replace）
* キャスト：未消化クリア

**エラー**

* 409 already_ended

---

#### 10.3.5 未消化ドリンクの取得（初期表示）

##### GET /cast/stream_sessions/:id/pending_drink_orders

**権限**：cast
**目的**：バックヤード右カラムの初期データ

---

#### 10.3.6 ドリンク消化（FIFO先頭のみ）

##### POST /cast/drink_orders/:id/consume

**権限**：cast（そのstream_session/boothに所属）
**条件**

* status=pending
* 対象注文が「そのセッションの先頭pending」であること（必須）

**成功**

* consumed_at
* new_pending_head_id（任意）
* updated_store_points（任意）

**通知（Turbo Streams）**

* キャスト：未消化キュー replace
* 顧客：演出（任意）

**エラー**

* 409 not_head（先頭じゃない）
* 409 already_consumed/refunded
* 409 session ended

---

### 10.4. 店舗管理者（Store Admin）向け

#### 10.4.1 店舗設定

##### GET /admin/store

##### PATCH /admin/store

**権限**：store_admin（そのstore）

---

#### 10.4.2 ドリンクメニュー管理

##### GET /admin/drink_items

##### POST /admin/drink_items

##### PATCH /admin/drink_items/:id

##### DELETE（論理削除推奨）/admin/drink_items/:id

**権限**：store_admin

---

#### 10.4.3 ブース管理（最低限）

##### GET /admin/booths

##### POST /admin/booths

##### PATCH /admin/booths/:id

**権限**：store_admin

---

#### 10.4.4 キャスト別数値一覧（集計）

##### GET /admin/cast_metrics?from=...&to=...

**権限**：store_admin
**返す**

* cast_user_id
* 配信売上（store_ledger_entries sum）
* 配信時間（stream_sessions合計）
* 売上/時間
* 実店舗売上（入力値：別テーブルにしてもOK。MVPはcast_metrics_inputでも可）

---

#### 10.4.5 モデレーション

##### POST /admin/store_bans

* customer_user_id
* reason

##### DELETE /admin/store_bans/:id（解除）

**権限**：store_admin

---

### 10.5. エラー仕様（共通）

#### 10.5.1 HTTPステータス（推奨）

* 401 Unauthorized：未ログイン
* 403 Forbidden：権限なし／BAN
* 404 Not found：対象なし
* 409 Conflict：状態不整合（配信終了済、FIFO違反、すでにliveなど）
* 422 Unprocessable Entity：入力不正
* 429 Too Many Requests：連投・過負荷
* 402 Payment Required：残高不足（ドリンク送信時）

#### 10.5.2 エラーコード（JSON）

アプリ側UIが分岐できるように、エラーコードを返す。

例：

* `banned`
* `insufficient_points`
* `session_ended`
* `booth_offline`
* `not_head`
* `rate_limited`

---

### 10.6. Turbo Streams（配信チャンネル）設計の紐付け

* コメント：`POST /comments` 成功 → `comments` ストリームに append
* ドリンク：`POST /drink_orders` / `consume` 成功 → `events` ストリームで

  * キャスト：pendingカラム replace
  * 顧客：演出 append（任意）
* 状態：席外し/終了 → 視聴画面の状態領域 replace

---

### 10.7. 決済（Stripe）連携の最小設計メモ（Phase1）

* `POST /wallet/purchases` で Checkout Session を作る
* `checkout.session.completed` webhook で wallet に purchase を加算（正）
* return_url はUI復帰用（正ではない）
* return_url復帰時に wallet を再取得し、未反映なら「反映中」表示して再取得

---

了解。続けて **権限マトリクス（ロール×操作）** と **監査ログ方針（Phase1）**、最後に **初期の負荷対策（最小）** を基本設計としてまとめます。

---

## 11. 権限マトリクス（Phase1）

### 11.1 ロール定義（再掲）

* 顧客（customer）
* キャスト（cast）
* 店舗管理者（store_admin）
* システム管理者（system_admin）

> ※キャスト/店舗管理者は `store_memberships` で店舗所属が正。
> 役割（role）は「アカウントの大分類」、所属は「その店舗で何ができるか」。

---

### 11.2 操作別（誰ができるか）

#### 顧客向け操作

| 機能         | customer |      cast      | store_admin | system_admin |
| ---------- | :------: | :------------: | :---------: | :----------: |
| ブース視聴（配信中） |     ✅    | ✅（デバッグ/確認用途なら） |   ✅（モニタ用途）  |       ✅      |
| コメント送信     |     ✅    |        ❌       |      ❌      |   ✅（運営テスト）   |
| ドリンク送信     |     ✅    |        ❌       |      ❌      |   ✅（運営テスト）   |
| ポイント購入     |     ✅    |        ❌       |      ❌      |   ✅（運営テスト）   |
| 購入履歴閲覧（自分） |     ✅    |        ❌       |      ❌      |       ✅      |

**追加条件**

* customer は **店舗BANされていないこと**
* booth が `live/away` であること（offlineは視聴は可、送信不可）

---

#### キャスト向け操作（ブース運用）

| 機能        | customer |    cast    |      store_admin      | system_admin |
| --------- | :------: | :--------: | :-------------------: | :----------: |
| 配信開始      |     ❌    | ✅（所属ブースのみ） |   ✅（強制開始はPhase2でも可）   |       ✅      |
| 席外し切替     |     ❌    | ✅（所属ブースのみ） |   ✅（強制切替はPhase2でも可）   |       ✅      |
| 配信終了      |     ❌    | ✅（所属ブースのみ） | ✅（強制終了はPhase1でも入れて良い） |       ✅      |
| 未消化ドリンク消化 |     ❌    | ✅（所属ブースのみ） |  ✅（代理消化は原則不要、Phase2）  |       ✅      |

**追加条件**

* cast は `store_memberships(role=cast)` かつ `booth_casts` の紐付けがあること
* 1ブース同時に複数キャストが触る可能性があるので、開始/終了/消化は **競合制御必須**

---

#### 店舗管理者向け操作（設定・モデレーション・集計）

| 機能           | customer |      cast      | store_admin | system_admin |
| ------------ | :------: | :------------: | :---------: | :----------: |
| 店舗設定（名称など）   |     ❌    |        ❌       |   ✅（自店舗のみ）  |       ✅      |
| ブース作成/編集     |     ❌    |        ❌       |   ✅（自店舗のみ）  |       ✅      |
| ブースにキャスト紐付け  |     ❌    |        ❌       |      ✅      |       ✅      |
| ドリンクメニュー設定   |     ❌    |        ❌       |      ✅      |       ✅      |
| キャスト別数値閲覧    |     ❌    | ✅（自分のみの簡易表示は可） |      ✅      |       ✅      |
| 店舗BAN（顧客）    |     ❌    |        ❌       |      ✅      |       ✅      |
| コメント削除（論理削除） |     ❌    | ✅（自配信内でミュート程度） |      ✅      |       ✅      |

---

#### システム管理者向け（全体管理）

| 機能         | system_admin |
| ---------- | :----------: |
| 店舗作成/停止    |       ✅      |
| ユーザー凍結/停止  |       ✅      |
| 全体BAN      |       ✅      |
| 不正調査（ログ閲覧） |       ✅      |

---

## 12. 監査ログ方針（Phase1）

### 12.1 監査ログの目的

* 「ポイントが消えた」「返却されない」「売上が合わない」などの問い合わせに **事実で回答できる**
* FIFO消化・返却・BANなどの操作が **追跡できる**
* Phase2以降の不正検知の土台

---

### 12.2 Phase1で“必ず残すべきログ”

Phase1は専用の `audit_logs` を作らなくても、以下が揃えば追跡可能にします。

#### (A) 金銭系（必須）

* `wallet_transactions`（購入/保留/返却/消化/調整）
* `drink_orders`（pending/consumed/refunded と日時）
* `store_ledger_entries`（売上確定の台帳）

> 金銭系は「台帳が監査ログ」になります。これが正。

#### (B) 重要操作（最低限）

* 配信開始/終了：`stream_sessions` がログになる
* 店舗BAN：`store_bans` がログになる
* コメント削除：`comments.deleted_at` をセット（誰がやったかはPhase1では簡略でもOK）

---

### 12.3 Phase1で“余力があれば入れると強い”監査（推奨）

#### audit_logs（1テーブル）

* actor_user_id（誰が）
* action（例：booth.end_stream / ban.create / drink.consume）
* target_type / target_id
* metadata（JSON：booth_id, stream_session_id, points等）
* created_at

これがあると運営・店舗の揉め事対応が楽になります。
MVPでもコストは小さいので、個人的には入れる推奨です。

---

## 13. 負荷対策（Phase1の最小セット）

### 13.1 コメント（スパム・連投）対策

* コメント送信は

  * 文字数上限（例：200）
  * 連投制限（例：1秒1回）
* BANユーザーは入室/送信/購入をブロック

> 実装は rack-attack などでOK（Rails流儀）

---

### 13.2 ActionCable（Turbo Streams）の最小運用

* チャンネルは **stream_session単位**
* 送るのは

  * コメント append
  * 未消化カラム replace
  * 状態表示 replace
    に限定（細かく送らない）

---

### 13.3 同接（Presence）はCableにしない

* 同接は **ポーリング**（10〜30秒）
* DB presencesで十分（Phase1）

---

### 13.4 FIFO消化は必ずDBで守る（最重要）

* `consume` は「先頭pending」をロックしてから更新
  → これで同時タップでも破綻しない

---

## 14. Phase1の設計完了チェック（ここまでで“基本設計Done”）

* ロールと権限の境界が決まっている
* 配信/ドリンク/ポイントの状態遷移が定義されている
* API一覧とエラー仕様がある
* Turbo Streamsの対象が決まっている
* 監査（台帳）で金銭系が追跡できる
* FIFO・返却がトランザクションで守られる


