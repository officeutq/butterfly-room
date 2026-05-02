# Metrics 設計

## 1. 概要

店舗管理者向けに、キャスト別の配信実績・売上実績を表示する。
現行実装では CastMetricsQuery が主な集計責務を持つ。

---

## 2. 対象

```text
CastMetricsQuery
views/admin/metrics/cast.html.erb
helpers/admin/metrics_helper.rb
```

---

## 3. 集計期間

デフォルトは直近30日。

```text
DEFAULT_RANGE_DAYS = 30
```

from / to を指定しない場合、現在時刻を基準に30日前から現在までを対象にする。

---

## 4. 対象キャスト

StoreMembership で対象店舗に cast として所属しているユーザーを対象にする。

```text
store_memberships.store_id = store.id
membership_role = cast
```

---

## 5. 売上集計

StoreLedgerEntry を stream_session 経由で集計する。

集計キー:

```text
stream_sessions.started_by_cast_user_id
```

集計値:

```text
sum(points)
```

つまり、配信を開始したキャストに対して、その配信で発生した店舗売上ポイントを紐づける。

---

## 6. 配信時間集計

StreamSession を対象に、指定期間と重なる部分だけを秒数計算する。

考え方:

```text
start = max(session.started_at, from)
end   = min(session.ended_at || now, to)
duration = end - start
```

配信中セッションは now を終了時刻として扱う。

---

## 7. 売上/時間

sales_per_hour は以下で算出する。

```text
stream_sales_points / stream_seconds * 3600
```

配信時間が0の場合は nil とする。

---

## 8. 現行で未実装・将来拡張

`real_store_sales_yen` は Row に存在するが nil 固定である。
将来的に、実店舗売上や外部売上を統合する余地がある。

---

## 9. 設計上の注意点

- 売上は StoreLedgerEntry 基準
- キャストへの紐づけは StreamSession.started_by_cast_user_id 基準
- 配信中セッションは now までの時間として集計される
- 期間境界をまたぐ配信は重なる部分のみ集計される
