# LP行動分析 Google Sheets連携運用手順

## 1. 目的と適用範囲

LP行動分析の日次集計をGoogleスプレッドシートへ出力するための、Google Cloud、Googleスプレッドシート、AWS Secrets Manager、EC2 IAM、環境変数の管理方法を定める。

- LP行動・登録・お問い合わせ実績の正本はRails DBとする
- Googleスプレッドシートは共有・レポート・二次集計用途とし、生イベントは保存しない
- Meta広告管理画面は広告成果、Microsoft Clarityはヒートマップ・録画の補助分析に使用する
- production（本番環境）とstaging（検証環境）の認証情報・出力先・IAM権限を分離する
- 秘密値や実際のSpreadsheet ID、Secret ARNはこの文書やGitHubへ記録しない

2026年8月9日時点では、環境別のGoogle Cloud・Spreadsheet・Secret・IAM・サーバー環境変数は手動設定済みである。Rails側の日次集計、Google Sheets API client、Job（定期処理）、手動再出力、失敗記録は#1032で実装済みで、stagingの実接続・手動出力・冪等再出力は#1033で確認済みである。production初回出力と自動出力の有効性確認は、別途承認を得たrolloutで行う。

横断シナリオ、staging実施結果、production持ち越し項目は[LP行動分析 横断検証・rollout手順](lp_analytics_validation.md)を参照する。

## 2. 構成と役割分担

| 対象 | production | staging |
| --- | --- | --- |
| Google Cloud project | `Butterflyve LP Analytics` | productionと同じproject内でアカウントを分離 |
| サービスアカウントの用途 | production日次集計の書き込み専用 | staging接続・出力検証専用 |
| サービスアカウント表示名（現行） | `Butterflyve LP Analytics Production` | `Butterflyve LP Analytics Staging` |
| Spreadsheet | production専用。実IDは公開しない | staging専用。実IDは公開しない |
| Rails管理worksheet | `daily_raw` | `daily_raw` |
| AWS Secrets Manager | production専用Secret | staging専用Secret |
| EC2 | `butterfly-room-app-1` | `butterfly-room-staging-app-1` |
| EC2 IAM role | `butterfly-room-ec2-role` | `butterfly-room-staging-ec2-role` |
| 環境設定 | `.env.production` | `.env.staging` |
| 自動出力 | `true`を設定済み。#1032のdeploy後に有効 | `false`を維持 |

サービスアカウントは人ではなくアプリケーションに属する単一目的のアカウントとして扱う。管理責任者はGoogle Cloud、AWS、productionサーバーへの管理権限を持つシステム管理責任者とする。担当者個人の氏名と引継ぎ先は公開リポジトリではなく、社内のアクセス権限管理台帳に記録する。

Google Cloud上の現行表示名は上表のとおり確認済みである。変更時は、権限を持つ担当者がGoogle Cloud Consoleの「IAMと管理」→「サービス アカウント」で対象環境とメールアドレスを照合する。メールアドレスやproject IDの実値はIssue・PRへ転記しない。

### 現在の確認状況

| 項目 | 状況 |
| --- | --- |
| Google Sheets API | 有効化済み |
| production / stagingサービスアカウントとJSON鍵 | 作成済み。鍵は対応Secretへ保存後、作業端末から削除済み |
| 鍵作成禁止policy | 鍵発行時のproject限定例外を解除し、親policy継承による禁止を再適用済み |
| Spreadsheetと`daily_raw` | 環境別に作成済み |
| Spreadsheet共有 | 対応環境のサービスアカウントだけが編集者。反対環境は権限なし。一般アクセスは制限付き。外部関係者への共有なし |
| 週次・graph・pivot用worksheet | 未作成。必要時に`daily_raw`とは別worksheetで作成する |
| AWS Secret | 環境別に作成済み。AWS管理KMS keyを使用し、自動rotationは無効 |
| EC2 IAM | 対応環境のSecretだけを取得可能。反対環境は`AccessDenied`確認済み |
| CloudTrail | 両環境の`GetSecretValue`成功eventを確認済み |
| EC2の環境設定 | 環境別に設定済み |
| app / workerへの設定反映 | 同じ環境別env fileを参照する構成を確認済み。stagingはcontainer再作成後のRails process、workerの定期task、無効化guardを確認済み。productionの再作成・実process確認は未実施 |
| Sheets API実接続 | staging専用出力先でread、手動出力、同日再出力を確認済み。productionは未実施 |
| 現行表示名 | production / stagingとも確認済み |

## 3. 実値の保存場所と確認手順

| 情報 | 正式な保存・確認場所 | 公開リポジトリでの扱い |
| --- | --- | --- |
| Google Cloud project ID | Google Cloud Consoleのproject情報 | 実値を書かない |
| サービスアカウント名・メール・鍵metadata | Google Cloud Consoleのサービスアカウント詳細 | 実値を書かない |
| Spreadsheet ID | 環境別SpreadsheetのURL、各EC2の環境設定 | 実値を書かない |
| worksheet名 | 各Spreadsheetと環境設定 | `daily_raw`のみ記載可 |
| Secret ID・名前・ARN | 環境別EC2の環境設定、AWS Secrets Managerの東京region | 実値を書かない |
| Secret値 | AWS Secrets Managerの対応環境Secret | 取得・表示・複製しない |
| staging Terraform参照名 | 権限を持つ運用端末のGit管理外`terraform.tfvars`または一時的な`TF_VAR_google_sheets_credentials_secret_name` | Gitへ追加しない |
| 管理責任者の個人情報 | 社内アクセス権限管理台帳 | 氏名等を書かない |

実値を確認するときはAWS Systems Manager Session Manager等の監査可能な管理経路を使用し、対象環境を先に確認する。`.env.production`や`.env.staging`全体を`cat`したり、ログ・画面共有・Issueへ貼り付けたりしない。

設定有無だけを確認する場合は、値を出力しない次の形式を使用する。`<ENV_FILE>`には対象環境のファイルを指定する。

```bash
env_file='<ENV_FILE>'
for key in \
  AWS_REGION \
  LP_ANALYTICS_SHEETS_EXPORT_ENABLED \
  GOOGLE_SHEETS_SPREADSHEET_ID \
  GOOGLE_SHEETS_WORKSHEET_NAME \
  GOOGLE_SHEETS_CREDENTIALS_SECRET_ID
do
  grep -Eq "^${key}=.+$" "$env_file" || {
    echo "missing: ${key}" >&2
    exit 1
  }
done
```

実値そのものが必要な担当者は、Google Cloud、Google Sheets、AWS Secrets Managerの各Consoleと、対象EC2上の該当する1変数だけを安全な対話セッションで照合する。確認結果には「一致／不一致」と確認日時だけを記録し、値を記録しない。

## 4. 環境変数

| 変数 | 区分 | 値の方針 |
| --- | --- | --- |
| `AWS_REGION` | 非秘密 | 両環境とも`ap-northeast-1` |
| `LP_ANALYTICS_SHEETS_EXPORT_ENABLED` | 非秘密 | productionは`true`、stagingは`false` |
| `GOOGLE_SHEETS_SPREADSHEET_ID` | 機微な識別子 | 環境ごとに別ID。実値をGit・Issue・PR・ログへ出さない |
| `GOOGLE_SHEETS_WORKSHEET_NAME` | 非秘密 | `daily_raw` |
| `GOOGLE_SHEETS_CREDENTIALS_SECRET_ID` | 機微な識別子 | 対応環境のSecretだけを指定。実値を公開しない |

サービスアカウントJSONやprivate keyは環境変数へ格納しない。環境変数に置くのはSecret IDだけとし、`LpAnalytics::Sheets::CredentialsProvider`がworker実行時に自身のEC2 IAM roleを使ってSecret値を取得する。

## 5. Secretの形式と管理

Secret値はGoogle Cloudが発行したサービスアカウントJSON全体を加工せずに保存する。次は構造確認用のダミーであり、実際の値として使用しない。

```json
{
  "type": "service_account",
  "project_id": "dummy-project-id",
  "private_key_id": "DUMMY_PRIVATE_KEY_ID",
  "private_key": "-----BEGIN PRIVATE KEY-----\nDUMMY_PRIVATE_KEY\n-----END PRIVATE KEY-----\n",
  "client_email": "dummy-environment@dummy-project-id.iam.gserviceaccount.com",
  "client_id": "000000000000000000000",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/dummy",
  "universe_domain": "googleapis.com"
}
```

- productionとstagingで別Secretを使用する
- KMS keyはAWS管理keyの`aws/secretsmanager`を使用する
- Secrets Managerの自動rotationは使用せず、サービスアカウント鍵と合わせて手動rotationする
- Secret値、version、private keyをTerraformで参照・管理しない
- Secret値をUser Data、systemd unit、Docker Compose、Issue、PR、ログへ埋め込まない
- metadata確認では`DescribeSecret`を使用し、`GetSecretValue`の応答を画面へ表示しない

Secretの存在とmetadataは、権限を持つ担当者がAWS Secrets Manager Consoleを東京regionに切り替え、対象環境のSecret詳細で確認する。「シークレットの値を取得する」は通常のmetadata確認では使用しない。

## 6. IAM最小権限

| Principal | 許可action | Resource |
| --- | --- | --- |
| production EC2 IAM role | `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` | production用Secret 1件のみ |
| staging EC2 IAM role | `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` | staging用Secret 1件のみ |
| `butterfly-room-staging-deployer` | `secretsmanager:DescribeSecret` | staging用Secret 1件のみ |

- production EC2 roleにstaging Secretへの権限を与えない
- staging EC2 roleとstaging deployerにproduction Secretへの権限を与えない
- staging deployerには`GetSecretValue`、`GetResourcePolicy`、`ListSecrets`を与えない
- staging EC2 IAMのSecret ARNはTerraformのexternal data sourceによる`DescribeSecret`結果から設定し、ARNをソースへ直書きしない
- production EC2 IAMは手動設定、staging EC2 IAMはTerraform管理という現行の管理境界を維持する

2026年8月9日に、production EC2からproduction Secret、staging EC2からstaging Secretへの取得成功と、互いの環境のSecretへの`AccessDenied`を確認済みである。確認時はSecret値を表示せず、対象metadataだけを照合した。

## 7. サービスアカウント鍵のrotation

定期rotationは90日ごとを運用標準とし、漏えいの疑い、担当者変更、誤共有、端末紛失があった場合は期限を待たずに実施する。実施日、対象環境、実施者、旧鍵の無効化・削除日時だけを社内運用記録へ残し、鍵IDや秘密値を公開記録へ残さない。

1. productionかstagingかを明示し、対象Spreadsheet・Secret・EC2 IAM roleを二者で確認する。
2. production作業ではメンテナンス時間と再起動・接続確認の承認を得る。
3. `iam.disableServiceAccountKeyCreation`の例外が必要な場合は、`Butterflyve LP Analytics` projectだけを一時的な対象にする。
4. 対象サービスアカウントに新しいJSON鍵を1つ発行する。
5. JSONファイルを表示せず、直ちに対応する環境の既存Secretへ新versionとして登録する。新しいSecretを増やさない。
6. 作業端末上のJSONファイルを安全に削除し、shell履歴、クリップボード、ダウンロード同期先に残っていないことを確認する。
7. #1033の接続確認手順で対応環境だけに接続できることを確認する。productionへの書き込み確認は別途承認を必要とする。
8. 新鍵での動作確認後、Google Cloudで旧鍵を先に無効化する。
9. 24時間以上監視し、旧鍵利用がないことと日次出力への影響がないことを確認してから旧鍵を削除する。
10. 一時的なproject例外を解除して親policy継承へ戻し、`iam.disableServiceAccountKeyCreation`が再度適用されていることを確認する。

Google Cloudは、不要な鍵をまず無効化し、利用されていないことを確認してから削除する運用を推奨している。将来、AWSからWorkload Identity Federationへ移行できる場合は、長期鍵を廃止するIssueを別途検討する。

## 8. 鍵の緊急失効

1. `LP_ANALYTICS_SHEETS_EXPORT_ENABLED=false`へ切り替える。productionでは承認を得てappとworkerを再作成する。
2. Google Cloudで疑わしい鍵を直ちに無効化する。サービスアカウント自体は影響範囲を確認せず削除しない。
3. 対応Spreadsheetから不審な共有先を削除する。
4. AWS Secrets Manager、CloudTrail、Google Cloudの監査情報から対象時間・Principal・操作を確認する。
5. 新しい鍵を発行し、前節の手順で対応環境のSecretを更新する。
6. stagingで安全に確認し、productionは承認後に復旧する。
7. 侵害された旧鍵は無効状態のまま影響調査後に削除する。

## 9. Spreadsheet共有権限

### 追加

1. Google Cloud Consoleで対象環境のサービスアカウントメールを確認する。
2. 対応環境のSpreadsheetを開き、「共有」でそのメールだけを編集者として追加する。
3. 一般アクセスが「制限付き」であることを確認する。
4. 反対環境のサービスアカウントが共有一覧にないことを確認する。
5. 外部関係者は原則閲覧者とし、編集者が必要な場合は対象・期間・理由をシステム管理責任者が承認する。

### 削除

1. 利用終了日と影響を確認する。
2. Spreadsheetの共有一覧から対象Principalを削除する。
3. サービスアカウントの場合は対応する自動出力を無効化し、日次処理停止を確認してから削除する。
4. 削除日時と理由を社内運用記録へ残す。

### worksheet運用

- `daily_raw`はRails管理領域とし、人が値、行、列、header、数式を直接追加・変更・削除しない
- 誤編集に気づいた場合はRails DBを正として`lp_analytics:sheets:export_date`または`export_range`で復旧する。手作業で帳尻を合わせない
- 週次集計、グラフ、ピボット、外部共有向け表示は別worksheetで作成し、`daily_raw`を参照する
- 週次CV率は日別CV率の平均ではなく、週間完了訪問数合計を週間LP訪問数合計で割る
- 現時点では週次用worksheetの作成は必須とせず、必要になった時点で追加する

## 10. appとSolid Queue workerの環境変数

現在のDocker Compose構成では次のように分離されている。

- productionのappとSolid Queue worker（非同期Job実行process）は、どちらも`./.env.production`を`env_file`として参照する
- stagingのappとworkerは、どちらも`${STAGING_ENV_FILE:-./.env.staging}`を参照する
- productionとstagingで別Compose file・別env file・別container名を使用する

この構造により両processへ同じ環境別設定を渡せることはソース上で確認済みである。stagingでは#1033でcontainer再作成後のRails実行環境、recurring task、手動Job、無効化guardを確認済みである。productionのcontainer再作成と実process確認は、停止影響の承認後に行う。

Docker Composeの`restart`だけでは変更した環境変数は反映されないため、反映時はcontainerを再作成する。productionでは勝手に実行せず、停止影響と実施時間の承認を得る。

```bash
# production: 承認後にだけ実行する
docker compose -f docker-compose.production.yml up -d --force-recreate app worker

# staging: stagingの作業手順に従って実行する
docker compose -f docker-compose.staging.yml up -d --force-recreate app worker
```

再作成後は値を表示せず、各containerで必須keyが存在し空でないこと、flagとworksheet名だけが期待値であることを確認する。Spreadsheet IDやSecret IDを標準出力へ出さない。stagingはflagが`false`のため、recurring Jobが起動してもSecret取得・Google Sheets出力を行わない。

## 11. production / staging誤接続の防止

1. サービスアカウント、Spreadsheet、Secret、EC2 IAM role、env fileを環境ごとに分離する。
2. productionは`LP_ANALYTICS_SHEETS_EXPORT_ENABLED=true`、stagingは`false`とし、`LpAnalytics::Sheets::ExportRecentDaysJob`がflagを明示的に判定する。
3. Secret IDとSpreadsheet IDを変更するときは、同じ環境の2項目を二者で照合する。
4. production roleからstaging Secret、staging roleからproduction Secretへの`AccessDenied`を維持する。
5. Google Sheets共有一覧で反対環境のサービスアカウントに権限がないことを確認する。
6. 起動・Jobログに実IDやSecret名を出さず、不可逆な出力先fingerprintだけを使用する。
7. productionへのテスト書き込みは明示承認なしに行わない。

## 12. Sheets API接続確認

Google Sheets API clientは#1032で実装し、通常testではAWS Secrets ManagerとGoogle APIをmockして実接続しない。共有画面上では、各サービスアカウントが対応Spreadsheetの編集者で、反対環境と一般アクセスには権限がないことを確認済みである。#1033ではstagingから空の`daily_raw`をreadし、匿名の日次4行を書込み、同日再出力後もaggregation keyの重複がないことを確認済みである。

#1033または将来の再検証で実接続確認を行うときは次の順序を守る。

1. 通常testではGoogle APIをmockし、実Spreadsheetへ接続しない。
2. 最初にstagingで、対応Spreadsheetへの`spreadsheets.get`相当のread-only metadata取得を行う。値や`daily_raw`の内容はログへ出さない。
3. stagingサービスアカウントからproduction Spreadsheetへのread-only metadata取得が`403`または`404`になることを確認する。成功した場合は書き込みへ進まず共有設定を修正する。
4. 編集権限の実地確認が必要な場合は、`daily_raw`ではなく承認済みの一時検証worksheetをstagingに作成し、固定dummy値を1セルへ書き、読取り後にworksheetを削除する。
5. productionサービスアカウントからstaging Spreadsheetへの拒否確認もread-onlyで行う。
6. productionへの実書き込み確認は、#1032の実装・mock test・staging確認完了後に、対象時刻と復旧方法を決めて別途承認を得る。

反対環境への「書込み拒否」を試すためにproductionへ意図的なwrite requestを送らない。共有設定に誤りがあった場合にproductionデータを変更する危険があるため、反対環境はread-only metadataの拒否と共有一覧で確認する。

## 13. CloudTrail確認

AWS CloudTrailはSecrets Manager API callを記録する。AWS Consoleで対象環境のregionを東京に合わせ、「CloudTrail」→「イベント履歴」から次を確認する。

- Event source: `secretsmanager.amazonaws.com`
- Event name: `GetSecretValue`または`DescribeSecret`
- Resource: 対応環境のSecret
- Principal: 対応環境のEC2 IAM role、またはstaging deployer
- Error code: 正常系では空、反対環境の拒否確認では`AccessDenied`

イベント詳細にはSecret名やARN等が含まれ得るため、Issue・PR・一般ログへ貼り付けない。確認記録には環境、日時、event name、成功／拒否、確認者だけを残す。

2026年8月9日にproduction・staging両方の`GetSecretValue`成功eventを確認済みである。

## 14. 日次Job・手動再出力・ログ

### 自動実行

`LpAnalytics::Sheets::ExportRecentDaysJob`をSolid Queue recurring taskとして、毎日02:20 JST（`20 2 * * * Asia/Tokyo`）に起動する。前日を終了日とする直近7日を古い順に処理する。

- `LP_ANALYTICS_SHEETS_EXPORT_ENABLED=true`かつ`RAILS_ENV=production`の場合だけ処理する
- stagingは`RAILS_ENV=production`でもflagを`false`にして自動出力しない
- 1日が失敗しても残りの日付を処理し、全日処理後にJobを失敗状態にする
- 429、5xx、timeout等はGoogle API call単位で最大3回、指数バックオフにより再試行する
- 401、403、header不一致等は再試行しない

### 手動再出力

stagingを含む手動出力はflagに関係なく明示的なRake taskから実行する。実行前に対象環境・Spreadsheet・日付を確認する。

```bash
# 1日
docker compose exec -T worker bin/rails "lp_analytics:sheets:export_date[2026-08-09]"

# 開始日・終了日を含む期間（最大366日）
docker compose exec -T worker bin/rails "lp_analytics:sheets:export_range[2026-08-01,2026-08-09]"
```

成功時は日付別の成功数を表示する。1日でも失敗した場合は失敗日とerror classだけを表示して非0で終了する。Spreadsheet ID、Secret ID、認証responseは表示しない。

### 出力状態

`lp_analytics_sheet_exports`で対象日、LP、出力先fingerprint、worksheetごとに次を確認できる。

- `status`: `pending` / `running` / `succeeded` / `failed`
- `attempt_count`, `row_count`, `payload_checksum`
- `started_at`, `completed_at`, `failed_at`
- `error_class`, 秘密値を除いた`error_message`, `needs_retry`

同じ対象の実行中Jobは二重実行せず、1時間以上更新されていない`running`状態だけを再取得可能とする。Google API通信中はDB transactionを保持しない。

### `daily_raw` schemaと復旧

1行目はRails管理headerであり、人が変更しない。主な列は`aggregation_key`、対象日、LP、流入元、UTM、端末、訪問数、スクロール到達数、主要セクション到達訪問数・到達率、登録・お問い合わせのCTA/フォーム/完了件数・完了訪問数・CV率、`exported_at`である。到達率とCV率は文字列ではなく0〜1の小数を`RAW`で書く。

- `device_type`は`pc`、`smartphone`、`tablet`のいずれかで、日次行と`aggregation_key`のdimension（集計軸）に含める
- 同じ日・LP・流入元・UTMでも端末が異なれば別行にする
- 202607版の主要セクションは`USAGE`、`STRENGTHS`、`SYSTEM`、`PRICING`、`FLOW`、`CAST`、`QA`、`bottom_cta`を対象にする
- 202609版の主要セクションは`existing_customer_opportunity`、`service_introduction`、`usage_mechanism`、`service_comparison`、`adoption_cost`、`usage_scenes`、`getting_started`、`final_opportunity_cta`を対象にする
- 各セクションは`section_<section>_visit_count`と`section_<section>_rate`を持ち、対象外LPのセクション列は0とする
- 各セクション到達率は同じ行の`section_<section>_visit_count / lp_visit_count`で、0除算時は`0.0`とする
- 端末別・週間等で複数行をまとめるCV率やセクション到達率は、率の平均ではなく対象行の分子合計を`lp_visit_count`合計で割る
- `device_type`とLP別セクション列の追加により従来の`lp_visit_count`以降の列位置が変わる。別worksheetの数式・pivot・外部連携が列番号や固定rangeを参照している場合は、新headerに合わせて更新する

- 空のworksheetだけは初回にheaderを作成する
- 既知の旧25列headerまたは202607版の42列headerと管理行は、最初の再出力時に共有列の値を維持したまま新58列へ展開する。新規列は対象日の再集計が完了するまで空欄とする
- 未知のheader不一致、duplicate key、管理行の一部欠損では書込みを停止する
- 既存keyは同じ行を更新し、新規keyは空き行または末尾へ追加する
- 再集計で消えた対象日行は空欄化する
- 書込みは`spreadsheets.values.batchUpdate`へまとめ、応答行数・セル数を検証する

障害時もRails DBを正本とし、Google Spreadsheetを手修正せず、原因修正後に上記Rake taskで再出力する。

### 端末・LP別セクション列追加時の移行

production / stagingの実Spreadsheetはソース変更やtestでは更新しない。deploy時は次の順序で移行する。

1. 対象環境とSpreadsheetを照合し、productionは自動出力を無効化してworkerへ反映する。stagingは`false`を維持する。
2. 新しいRails codeをdeployし、app / workerが同じ新imageを使用していることを確認する。
3. stagingで、LP行動分析の最初の保存日から前日までを`lp_analytics:sheets:export_range`で再出力する。必要な場合だけ当日を`export_date`で明示的に出力する。
4. 旧25列または42列headerが新58列へ移行し、`device_type`、LP別の主要セクション到達訪問数・到達率、既存の訪問数・CV率がRails DBと一致することを確認する。
5. aggregation keyの空欄・重複、部分行、秘密値・個人情報の出力がないことを確認する。別worksheetの数式・pivot・外部連携が旧列位置を参照していないかも確認する。
6. productionは別途承認を得て同じ期間を再出力する。旧集計keyは端末軸を持たないため、全対象期間の再出力が完了するまで端末別集計へ使用しない。
7. productionの照合完了後に自動出力を有効化してworkerを再作成し、次回02:20 JSTの直近7日再出力を確認する。

移行処理が自動で受け付けるのは、この変更直前のRails管理headerと完全一致するworksheetだけである。独自列、数式、列順変更等がある場合は`HeaderMismatchError`で停止するため、`daily_raw`を手修正せず、影響を確認してからRails DBを正として復旧する。

## 15. 障害の切り分けと復旧

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| Jobが起動しない | flag、worker稼働、#1032のrecurring設定 | stagingはfalseが正常。productionは承認後に設定・workerを再確認 |
| 必須設定不足 | 値を表示せず環境変数の存在を確認 | 対応環境のenv fileを修正し、承認後にapp・workerを再作成 |
| AWS `AccessDenied` | EC2 IAM role、Secret環境、CloudTrail | roleとSecretの組合せを修正。権限を`*`へ広げない |
| Secretが見つからない | region、Secret ID、削除予定 | metadataだけを確認し、対応環境のIDへ修正 |
| Google認証失敗 | 鍵の有効状態、Secret version、時刻 | 新鍵へrotation。private keyをlogへ出さない |
| Sheets `403` / `404` | Spreadsheet環境、共有一覧、API有効化 | 対応サービスアカウントだけを共有し、反対環境へ権限追加しない |
| header不一致・重複key | #1032の検証結果 | 書込みを停止し、`daily_raw`を手修正せず原因を直して再出力 |
| 429 / 5xx / timeout | #1032の失敗状態とretry結果 | ユーザー処理から分離した有限retry後、未成功日だけ再出力 |
| 誤環境接続 | flag、IAM、共有、出力先fingerprint | 自動出力停止、権限削除、影響確認、Rails DBから正しい環境へ再出力 |

Google Sheets障害はLP閲覧、店舗登録、お問い合わせ、Rails DB保存へ影響させない。production復旧でcontainer再作成やSpreadsheet書込みが必要な場合は、必ず事前承認を得る。

## 16. 記録禁止情報

次の実値をGit、コミット、Issue、PR、通常log、plan出力、User Data、systemd unit、Docker Composeへ記録しない。

- サービスアカウントJSONとprivate key
- Google access token、refresh token、認証header
- production / stagingのSpreadsheet ID
- サービスアカウントメール、project ID、client ID、private key ID
- Secret値、Secret名、Secret ID、Secret ARN、Secret versionの実値
- `.env.production`、`.env.staging`の内容
- フォーム入力内容、氏名、メールアドレス、電話番号等の個人情報

例示には`dummy-project-id`、`<PRODUCTION_SPREADSHEET_ID>`、`<STAGING_SECRET_ID>`等のダミーだけを使用する。エラーlogは認証response bodyやrequest payloadを出さず、環境、対象日、error class、HTTP status、retry要否だけを記録する。

## 17. Issue境界

#1027では、Google Cloud・Spreadsheet・Secret・IAM・環境設定の準備、環境分離、運用手順、Docker Compose上のapp / worker参照経路までを完了した。#1032では日次集計・API client・冪等出力・Job・Rake task・失敗状態を実装した。

実環境での次の確認は#1033でstaging分を完了した。

- app / workerの実行環境とworker無効化guard
- staging専用Spreadsheetのread、手動出力、冪等再出力
- recurring Job設定と手動再出力の実process確認

承認後のproduction実書き込み、Rails DBとの初回突合、自動出力確認は未実施である。#1033のstaging検証を根拠に自動実行せず、[LP行動分析 横断検証・rollout手順](lp_analytics_validation.md)のproductionチェックリストに従う。

#1027対応ではproduction containerの再作成、Spreadsheetへの書き込み、Secret値取得を行わない。

## 18. 公式資料

- [Google Cloud: Best practices for using service accounts securely](https://docs.cloud.google.com/iam/docs/best-practices-service-accounts)
- [Google Cloud: Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)
- [Google Cloud: Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete)
- [AWS Secrets Manager: Log events with AWS CloudTrail](https://docs.aws.amazon.com/secretsmanager/latest/userguide/monitoring-cloudtrail.html)
- [Docker: `docker compose restart`](https://docs.docker.com/reference/cli/docker/compose/restart/)
