# ステージングDB準備

この手順はTerraformでは実行しません。DB管理者が内容をレビューし、`corporate-prod`上で手動実行します。本作業ではRDS接続もSQL実行も行っていません。

## 前提

- 接続先ホストが`corporate-prod`のエンドポイントである
- 管理用の初期接続DBが`postgres`である
- 作成対象が`butterfly_room_staging`と`butterfly_room_staging_user`である
- 本番DB名`butterfly_room_production`を`DATABASE_URL`へ設定しない
- DB管理者認証情報と新規パスワードをGit、シェル履歴、画面共有へ残さない

## 実行例

接続情報は組織の安全な保管先から取得します。次のコマンドのホスト名と管理ユーザー名は人間が確認して置き換えます。

```powershell
$env:PGSSLMODE = "verify-full"
$env:PGSSLROOTCERT = "C:\path\to\global-bundle.pem"
psql --host "<corporate-prod endpoint>" --port 5432 --username "<database administrator>" --dbname postgres --file ops/staging/create_staging_database.sql
```

SQLは新規ロールのパスワードを対話入力で求めます。再実行時は既存ロールのパスワードを変更せず、権限属性、DB所有者向け権限、schema権限を再確認します。パスワード変更が必要な場合は、別途承認された安全な手順で行います。

## 実行前確認

```sql
SELECT current_database(), current_user, inet_server_addr(), inet_server_port();
SELECT datname FROM pg_database WHERE datname IN ('butterfly_room_production', 'butterfly_room_staging');
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname = 'butterfly_room_staging_user';
```

結果の接続先、DB名、ユーザー名が想定外なら中止します。

## 実行後確認

```sql
SELECT datname, pg_get_userbyid(datdba) AS owner
FROM pg_database
WHERE datname = 'butterfly_room_staging';

SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles
WHERE rolname = 'butterfly_room_staging_user';

SELECT has_database_privilege(
  'butterfly_room_staging_user',
  'butterfly_room_staging',
  'CONNECT'
) AS can_connect_staging;

SELECT has_database_privilege(
  'butterfly_room_staging_user',
  'butterfly_room_production',
  'CONNECT'
) AS can_connect_production;
```

PostgreSQLでは`PUBLIC`に付与された`CONNECT`権限が全ロールへ波及します。最後の値が`true`でも、このテンプレートは本番DBの権限を付与していません。厳密に接続自体を拒否するには本番利用者への個別GRANTと`PUBLIC`からのREVOKEが必要ですが、本番への影響があるため、このSQLでは実施しません。DB管理者が既存ACLを調査して別途判断してください。

作成後はステージングEC2から`db:prepare`を実行し、`APP_ENV=staging`でのみステージングseedを実行します。本番データはコピーしません。
