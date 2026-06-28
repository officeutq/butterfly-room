# 月次精算生成 systemd timer 運用手順

## 目的

月次精算生成を systemd timer（Linux の定期実行機能）で自動実行する。

- 毎月1日 13:00 JST に、JST 基準の前月分を生成する。
- EC2（本番サーバー）は UTC 運用のため、timer は `04:00 UTC` に設定する。
- 生成するのは `monthly / draft` の `Settlement` のみとする。
- `confirmed`、CSV出力、`paid` 化、支払明細書PDF発行は system_admin（システム管理者）が手動で行う。

## 前提

- 月次精算生成の業務処理は `Settlements::MonthlyGenerateService` を正とする。
- #932 の system_admin 画面からの手動実行導線は残す。
- #275 では Rake task（Railsタスク）と systemd timer による production（本番環境）自動実行を扱う。
- `config/recurring.yml` と `app/jobs` は使わない。
- systemd timer は複数月分の未実行を自動で順番に埋めない。長期停止後は任意月指定で古い月から手動実行する。

## Rake task

通常実行:

```bash
bin/rails settlements:monthly_generate
```

JST 基準の前月分を生成する。

任意月の救済実行:

```bash
bin/rails "settlements:monthly_generate[2026-05]"
```

この例では、2026年5月分を生成する。対象期間は 2026-05-01 00:00 JST から 2026-06-01 00:00 JST の直前まで。

ログ例:

```text
[MonthlySettlement] target=2026-05-01..2026-06-01 created=0 carryover=1 skipped=0
[MonthlySettlement] carryover_detail store_id=12 reason=below_min_payout detail=payable_total=6300
```

ログの意味:

- `created`: 作成した `Settlement` 件数
- `carryover`: 最低支払額未満により新しく `SettlementCarryover` に繰り越した店舗数
- `skipped`: 既存精算で対象期間が埋まっている、または既に繰越処理済みなどで新規処理しなかった店舗数

不正な月指定では非0終了する。

```bash
bin/rails "settlements:monthly_generate[2026-13]"
```

## systemd ファイル

リポジトリにはテンプレートとして以下を置く。

- `ops/systemd/butterflyve-monthly-settlement.service`
- `ops/systemd/butterflyve-monthly-settlement.timer`

実際のEC2へは、運用時に `/etc/systemd/system/` へコピーする。

既存の production 手順に合わせ、テンプレートでは作業ディレクトリを `/home/ec2-user/apps/butterfly-room` としている。配置先が異なる環境では、service ファイル内のパスを実環境に合わせて置き換える。

## EC2 反映手順

### 1. systemd ファイルを配置する

```bash
sudo cp ops/systemd/butterflyve-monthly-settlement.service /etc/systemd/system/
sudo cp ops/systemd/butterflyve-monthly-settlement.timer /etc/systemd/system/
```

### 2. systemd を reload する

```bash
sudo systemctl daemon-reload
```

### 3. timer を有効化する

```bash
sudo systemctl enable --now butterflyve-monthly-settlement.timer
```

### 4. 次回実行予定を確認する

```bash
systemctl list-timers '*butterflyve*'
```

### 5. calendar を確認する

EC2 は UTC 運用のため、`04:00 UTC` が `13:00 JST` に相当することを確認する。

```bash
systemd-analyze calendar "*-*-01 04:00"
```

## 手動実行

systemd service として実行する。

```bash
sudo systemctl start butterflyve-monthly-settlement.service
```

Rails task を直接実行する。

```bash
docker compose \
  -f docker-compose.production.yml \
  --env-file .env.production \
  exec -T app bin/rails settlements:monthly_generate
```

任意月を救済実行する。

```bash
docker compose \
  -f docker-compose.production.yml \
  --env-file .env.production \
  exec -T app bin/rails "settlements:monthly_generate[2026-05]"
```

## ログ確認

```bash
sudo journalctl -u butterflyve-monthly-settlement.service -n 200 --no-pager
```

成功時は、次のように対象期間と件数が出る。

```text
[MonthlySettlement] target=2026-05-01..2026-06-01 created=1 carryover=0 skipped=0
```

## 失敗時の対応

1. `journalctl` でエラー内容を確認する。
2. 原因を修正する。
3. 必要に応じて `settlements:monthly_generate[YYYY-MM]` を古い月から順番に実行する。

`Persistent=true` により、サーバ停止中に実行予定時刻を過ぎた場合は復帰後に1回実行される。ただし、複数月分の未実行を自動で順番に埋めるものではない。

## イベント記録

system_admin 画面から手動実行した場合は、#932 の実装により、作成された `Settlement` ごとに `SettlementEvent.created` を記録する。

systemd timer / Rake task からの実行では、実行者となる system_admin ユーザーが存在しない。そのため `actor_user: nil` のまま `Settlements::MonthlyGenerateService` を呼び、`SettlementEvent.created` は記録しない。

`SettlementCarryover` のみ作成される場合は、紐づく `Settlement` が存在しないため `SettlementEvent` は記録しない。繰越結果は Rake task のログと `SettlementCarryover` のレコードで確認する。

## 非スコープ

この運用では以下を行わない。

- 月次精算の自動確定
- CSV出力の自動化
- 銀行画面へのCSVアップロード自動化
- `paid` 自動化
- 銀行API連携
- ActiveJob（Railsの非同期ジョブ）化
- `config/recurring.yml` への登録
- DB上のバッチ実行ログテーブル追加
- system_admin 画面の月次生成導線変更
