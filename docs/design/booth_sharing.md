# ブース共有・配信共有設計

## 1. 目的

ブース共有と配信共有でURLとOGPを分離し、SNSクローラーと人間のどちらにも同じ公開HTMLを返す。

共有専用URLは未ログイン公開を新設するものではない。通常の `/booths/:id` は、公開店舗に属する未アーカイブのブースであれば、未ログインでも読み取り専用で閲覧できる。共有専用URLは、ブース単位と `StreamSession` 単位でOGPおよびSNSキャッシュを分離するために使用する。

## 2. 配信状態の前提

- `Booth.status` は `offline / standby / live / away` を持ち、視聴可否を含む現在の表示状態を表す
- `StreamSession.status` は `live / ended` だけを持つ
- standby開始時に `StreamSession(status: live)` を1件作成し、`Booth.current_stream_session_id` に設定する
- standbyからlive、liveとawayの相互遷移では同じ `StreamSession` を利用する
- 配信終了時にその `StreamSession` をendedへ変更し、Boothをoffline、`current_stream_session_id` をnilにする
- 配信タイトルはcurrent session一致かつBoothがstandbyの場合だけ編集できる
- 表示タイトルは `StreamSession.title.presence || Booth.name` とする

共有URLはstandby開始から配信終了まで同じstream IDを使用する。ended済みでも対象ブースに属するstreamは、ブースが現在の公開条件を満たす限り配信共有OGPに利用できる。

## 3. 共有の区分

| 区分 | 共有元 | URL | 表示名の起点 |
| --- | --- | --- | --- |
| ブース共有 | キャスト用ブース情報画面 | `/booths/:id/share` | `Booth#primary_cast_user` |
| 配信共有 | キャスト配信画面 | `/booths/:id/share?stream=<stream_session_id>` | `StreamSession#started_by_cast_user` |

ブース共有では、Boothがcurrent sessionを持っていてもstreamを付けない。配信共有ではstandby / live / awayのどの状態でも、画面が保持するcurrent `StreamSession` のIDを付ける。

## 4. 公開条件と認証境界

- 共有ページは `authenticate_user!` の対象外とする
- ブースは `Booth.active.in_published_stores` から取得する
- 公開店舗の未アーカイブブースは、未ログイン・ログイン済み・クローラーのいずれも200 OKとする
- 非公開店舗、アーカイブ済みブース、存在しないブースは404とする
- User-Agentによる分岐を行わず、同じリクエスト条件には同じHTMLとOGPを返す
- 通常の `/booths/:id` の未ログイン読み取り専用表示は変更しない
- 通常の `/booths/:id/enter` は未ログインを `/welcome` へ転送する既存仕様を維持する

## 5. streamの解決

streamはグローバル検索せず、取得済みブースの `stream_sessions` 関連からID一致で解決する。

| 指定 | 扱い |
| --- | --- |
| 指定なし | ブース共有 |
| 対象ブースのcurrent stream | 配信共有 |
| 対象ブースのended stream | 配信共有 |
| 存在しないID | ブース共有へフォールバック |
| 数値として不正な値 | ブース共有へフォールバック |
| 別ブースのID | ブース共有へフォールバック |

無効なstream値をcanonical URLやOGPへ残さず、別ブースの情報を出力しない。

## 6. OGP生成規則

サイト名は `Butterflyve（バタフライブ）`、`og:type` は `website`、`twitter:card` は `summary_large_image` とする。

| 項目 | ブース共有 | 配信共有 |
| --- | --- | --- |
| title | `Booth.name` | `StreamSession.title.presence || Booth.name` |
| descriptionの表示名 | 公開可能な `primary_cast_user` | 公開可能な `started_by_cast_user` |
| description（表示名あり） | `〇〇のライブ配信をButterflyveで楽しもう` | `〇〇のライブ配信をButterflyveで楽しもう` |
| description（表示名なし） | `ライブ配信をButterflyveで楽しもう` | `ライブ配信をButterflyveで楽しもう` |
| image | `Booth.thumbnail_image`、未設定時は `logo.png` | 同左 |
| `og:url` / canonical | streamなし共有URL | 有効なstream ID付き共有URL |

画像URLと共有URLは絶対URLで生成する。

### 6.1 公開可能な表示名

次の両方を満たす場合だけ `display_name` を利用する。

- ユーザーが論理削除されていない
- `display_name` が空欄ではない

条件を満たさない場合は固定文へフォールバックし、メールアドレスや管理情報を代用しない。

## 7. 人間アクセスと専用layout

共有ページはOGPを含むHTMLを200 OKで返し、既存の `auto_redirect_controller.js` をdelay `0` で使用して通常の `/booths/:id` へ即時遷移する。遷移先にはstreamを持ち込まない。

JavaScript無効時のため、通常ブースへのリンクを本文に表示する。

共有ページは専用の最小layoutを使用し、次だけを出力する。

- OGP、canonical、robots meta
- JavaScript遷移に必要なimportmap
- 通常ブースへのリンク

通常のapplication layout、ログイン中ユーザーのメールアドレス、管理導線、配信視聴UI、コメント、ドリンク機能は出力しない。公開情報はブース名、ブースサムネイル、配信タイトル、公開可能な表示名に限定する。

## 8. Web Share APIへ渡す値

共通の `share_controller.js` は変更せず、各Viewがdata属性を設定する。

### 8.1 ブース情報画面

- title: `Butterflyve`
- url: streamなし共有専用URLの絶対URL
- text（公開可能な専属キャスト表示名あり）: `〇〇のブースはこちら🦋`
- text（表示名なし）: `Butterflyveのブースはこちら🦋`
- ボタン文言: `ブースを共有`

### 8.2 キャスト配信画面

- title: `Butterflyve`
- url: current `StreamSession` ID付き共有専用URLの絶対URL
- text（公開可能な配信開始者表示名あり）: `〇〇の配信はここから！遊びに来てね🦋`
- text（表示名なし）: `配信はここから！遊びに来てね🦋`
- `aria-label`、title、非表示文言: `配信を共有`

## 9. キャッシュと検索エンジン

- `1 StreamSession = 1共有URL` とする
- standby中のタイトル変更後に同一URLのSNSキャッシュが残ることを許容する
- timestamp等のキャッシュバスターを追加しない
- SNSキャッシュの強制更新処理を実装しない
- 共有ページは `noindex` とする
- 共有URLをsitemapへ追加しない

## 10. 責務分担

- route: `BoothsController` のmember actionとして共有URLを公開する
- Controller: 公開ブースとstreamの解決、OGP値の設定、レスポンスに留める
- View / 専用layout: 公開情報、meta、遷移先、フォールバックリンクを出力する
- `share_controller.js`: data属性のtitle / text / urlをWeb Share APIへ渡す
- `auto_redirect_controller.js`: 指定URLへのJavaScript遷移を行う

DB schema、`Booth` / `StreamSession` の状態遷移、視聴・コメント・ドリンク・金銭処理は変更しない。

## 11. テスト方針

- 未ログイン、ログイン済み、代表的なクローラーUser-Agentで共有ページが200 OKとなる
- 公開店舗 / 非公開店舗、active / archivedブースの公開条件
- streamなし、有効、ended、不存在、不正値、別ブースの解決結果
- 配信タイトル、サムネイル、表示名の各フォールバック
- OGP、絶対画像URL、`og:url`、canonical、Twitter Card、`noindex`
- JavaScript遷移先とJavaScript無効時リンク
- 共有ページにメールアドレス等の非公開情報が含まれない
- ブース情報画面と配信画面の共有data属性
- 通常ブースの未ログイン読み取り専用表示と、未ログインの`booths#enter`転送の回帰
- sitemapへ共有URLを追加していないこと
