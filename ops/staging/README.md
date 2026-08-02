# ステージングDB準備・分離手順

このディレクトリのSQLはTerraformや自動デプロイから実行しません。Amazon RDS for PostgreSQLの管理者が、対象、接続中ユーザー、影響範囲を確認して手動実行します。DBパスワード、接続文字列、エンドポイントはGit、SQLファイル、シェル履歴へ保存しません。

## SQLファイル

| ファイル | 用途 | 変更の有無 |
| --- | --- | --- |
| `create_staging_database.sql` | staging role、DB、staging側ACLを作成・更新 | staging側のみ変更 |
| `restrict_production_database_access.sql` | production DBのPUBLIC接続権限を分離 | **本番DBの権限を変更** |
| `verify_staging_database_isolation.sql` | role、DB、schema、object権限を検証 | 参照専用 |

## この環境での実施結果（2026-08-02）

これは再利用手順ではなく、現在のButterfly Room環境で確認済みの結果です。

- PostgreSQL server 18.3、psql client 18.4で実施した
- staging EC2からRDSのTCP/5432へ到達し、TLS接続を確認した
- `butterfly_room_staging_user`を`LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`で作成した
- `butterfly_room_staging`を作成し、ownerをstaging userにした
- staging userのstaging DB `CONNECT` / `TEMPORARY`と、`public` schema `USAGE` / `CREATE`がtrueであることを確認した
- production DBの`PUBLIC`にあったデフォルトの`CONNECT` / `TEMPORARY`を削除した
- production用の`postgres`へ`CONNECT` / `TEMPORARY`、`rdsproxyadmin`へ`CONNECT`を明示的に残した
- staging userからproduction DBへの実接続が拒否されることを確認した
- 変更前後で本番Railsの既存接続が維持され、サービス影響がないことを確認した
- DB作成時に付与した`postgres`からstaging roleへの一時membershipが残っていないことを確認した

## 1. 前提確認

### PostgreSQL client

serverと同じmajor versionのPostgreSQL 18系clientを使用します。

```bash
psql --version
```

### staging EC2からRDS TCP/5432への到達

次はTCP到達だけを確認し、PostgreSQL認証は行いません。

```bash
timeout 5 bash -c '</dev/tcp/<rds-endpoint>/5432'
```

失敗した場合はRDSのsecurity group、VPC routing、DNS解決を確認し、SQLを実行しません。

### 接続条件

- RDS instance: `corporate-prod`
- 管理ユーザー: `postgres`
- 初期接続DB: `postgres`
- staging DB: `butterfly_room_staging`
- staging role: `butterfly_room_staging_user`
- TLS: `sslmode=verify-full`を推奨し、RDS CA bundleを使用する

接続後に`conninfo`または次の参照SQLでTLSを確認します。

```sql
SELECT ssl, version, cipher
FROM pg_stat_ssl
WHERE pid = pg_backend_pid();
```

## 2. staging roleとDBの作成

リポジトリのrootから実行します。接続先と証明書パスは安全な保管先から指定し、コマンド例へ実値を書き戻しません。

```bash
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/path/to/global-bundle.pem
psql --host '<rds-endpoint>' --port 5432 --username postgres --dbname postgres \
  --file ops/staging/create_staging_database.sql
```

このSQLは次を行います。

1. staging roleがなければ作成し、制限属性を毎回適用する
2. `\password butterfly_room_staging_user`でパスワードを非表示入力する
3. staging DBがなければstaging roleをownerとして作成する
4. staging DBの`PUBLIC`権限を削除し、staging roleへ`CONNECT` / `TEMPORARY`を付与する
5. staging DBの`public` schemaをstaging role所有とし、`USAGE` / `CREATE`を付与する
6. 一時的に変更した管理者membershipを元の状態へ戻す

`\password`が成功しても、`ALTER ROLE`などの完了メッセージが表示されず、そのままpsql promptへ戻ることがあります。メッセージの有無で成功判定せず、後述のstaging userによる実ログインで確認します。

### Amazon RDSのSET ROLE制約

PostgreSQL 18では、別roleをownerに指定する`CREATE DATABASE`の実行者に、そのowner roleへ`SET ROLE`できる権限が必要です。Amazon RDSの`postgres`は完全なPostgreSQL superuserではないため、権限がなければ次のエラーになります。

```text
ERROR: must be able to SET ROLE "butterfly_room_staging_user"
```

作成SQLは実行前に次を記録します。

- 管理ユーザーが既にstaging roleへ`SET ROLE`できるか
- 直接membershipが既にあるか
- 直接membershipの`set_option`がtrueか

必要な場合だけ`GRANT butterfly_room_staging_user TO CURRENT_USER WITH SET TRUE`を実行します。SQL自身が新規membershipを作った場合だけ`REVOKE`し、既存membershipの`SET`だけ一時的に有効化した場合は`SET FALSE`へ戻します。既に存在したmembershipを削除しません。

[PostgreSQL 18のGRANT](https://www.postgresql.org/docs/18/sql-grant.html)と[CREATE DATABASE](https://www.postgresql.org/docs/18/sql-createdatabase.html)の仕様を前提にしています。

### 異常終了時のmembership復旧

`CREATE DATABASE`はtransaction内で実行できません。SQLがcleanup前に停止した場合、一時membershipが残る可能性があります。再実行する前に、作成SQLが表示した「Membership state before staging owner operations」と次の現在値を比較します。

```sql
SELECT
  member_role.rolname AS member_role,
  membership.admin_option,
  membership.inherit_option,
  membership.set_option
FROM pg_auth_members membership
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
JOIN pg_roles member_role ON member_role.oid = membership.member
WHERE granted_role.rolname = 'butterfly_room_staging_user'
  AND member_role.rolname = 'postgres';
```

スクリプト実行前に直接membershipがなかったことを確認できる場合だけ、次を実行します。

```sql
REVOKE butterfly_room_staging_user FROM postgres;
```

実行前から直接membershipがあり、`set_option=false`だった場合は、membershipを削除せず元の`SET FALSE`へ戻します。

```sql
GRANT butterfly_room_staging_user TO postgres WITH SET FALSE;
```

実行前の状態を確認できない場合は推測で`REVOKE`せず、人間がmembershipの所有目的を確認します。復旧後、前述の参照SQLと`verify_staging_database_isolation.sql`で一時membershipが残っていないことを確認します。

### staging userによる実ログイン

パスワードをコマンドラインへ含めず、promptで入力します。

```bash
psql --host '<rds-endpoint>' --port 5432 \
  --username butterfly_room_staging_user \
  --dbname butterfly_room_staging
```

接続後に次を確認します。

```sql
SELECT current_database(), current_user;
SELECT has_database_privilege(current_user, current_database(), 'CONNECT');
SELECT has_database_privilege(current_user, current_database(), 'TEMPORARY');
SELECT has_schema_privilege(current_user, 'public', 'USAGE');
SELECT has_schema_privilege(current_user, 'public', 'CREATE');
```

## 3. production DBの接続分離

この手順は**本番DBの権限を変更**します。staging DB作成SQLとは分離し、Terraformやデプロイから実行しません。

PostgreSQLのDBは、`datacl`がNULLでも`PUBLIC`のデフォルト権限により全login roleが`CONNECT` / `TEMPORARY`を持つことがあります。変更前に必ず次を確認します。

- production DBのownerと`datacl`
- productionへ現在接続しているuser、`application_name`、client、接続数
- login可能な全role
- productionアプリが実際に使うrole
- `postgres`がproductionへ接続可能であること
- `rdsproxyadmin`が存在すること
- staging userのproduction `CONNECT` / `TEMPORARY`

`restrict_production_database_access.sql`はこれらを表示し、接続DB、実行ユーザー、DB owner、必要roleをguardで検証します。確認文字列が完全一致した場合だけ、次を1 transactionで行います。

- `PUBLIC`からproductionの`CONNECT` / `TEMPORARY`を削除
- 確認済みproduction app roleである`postgres`へ`CONNECT` / `TEMPORARY`を明示付与
- `rdsproxyadmin`へ`CONNECT`を明示付与

```bash
psql --host '<rds-endpoint>' --port 5432 --username postgres \
  --dbname butterfly_room_production \
  --file ops/staging/restrict_production_database_access.sql
```

`REVOKE CONNECT`は通常、既存sessionを切断しません。一方で新規接続には直ちに影響するため、transaction直後に次を確認します。

- 本番Railsの既存接続が残っている
- production app roleで新規接続できる
- staging userでproductionへ新規接続できない
- 本番health checkと主要画面が正常

production app roleが`postgres`以外にもある場合は、このSQLを実行する前にそのroleへの`CONNECT` / `TEMPORARY`付与をレビューし、SQLを修正します。既存接続があるという理由だけで、新規接続権限を省略しません。

## 4. 参照専用の分離検証

```bash
psql --host '<rds-endpoint>' --port 5432 --username postgres --dbname postgres \
  --file ops/staging/verify_staging_database_isolation.sql
```

検証SQLは次を確認します。

- staging roleの存在と制限属性
- staging DB owner、`CONNECT` / `TEMPORARY`
- staging `public` schema owner、`USAGE` / `CREATE`
- production DBのstaging user向け`CONNECT` / `TEMPORARY` / `CREATE`
- production `public` schemaの`USAGE` / `CREATE`
- productionのtable DML、sequence、function/procedure権限
- `postgres`のproduction `CONNECT` / `TEMPORARY`
- `rdsproxyadmin`のproduction `CONNECT`
- 管理ユーザーの一時membershipが残っていないこと

functionはPostgreSQLのデフォルトで`PUBLIC`へ`EXECUTE`が付く場合があります。予期しない行が出ても検証SQLは権限変更せず、人間が影響を判断します。

### staging userからproductionへの実接続拒否

SQL関数の結果だけでなく、別processで実接続が拒否されることを確認します。パスワードはpromptで入力します。

```bash
psql --host '<rds-endpoint>' --port 5432 \
  --username butterfly_room_staging_user \
  --dbname butterfly_room_production
```

期待値は`permission denied for database butterfly_room_production`です。

## 5. 秘密情報の扱い

- SQL、README、PRへDBパスワードや`DATABASE_URL`を書かない
- `PGPASSWORD`をshell historyへ残さない
- `\password`の非表示入力を使用する
- endpoint、内部IP、接続文字列を不要にログやPRへ転載しない
- `.env.staging`はEC2上でmode 600とし、Git管理しない
