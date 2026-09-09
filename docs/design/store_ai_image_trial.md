# 初回店舗設定の画像取得試作（#1224）

最終確認日：2026-09-09。親Epic：#1219。

## 実装した範囲

初回店舗設定で、確認済みの公式サイト、X、Instagram、TikTok、YouTubeの順に代表画像を取得する。画像未設定・未編集のフォームに中央切り抜きで仮反映し、既存の画像メニューから再編集・差し替え・削除できる。

AIは従来のテキスト検索を1回だけ行う。画像の追加AI検索を使わず、同じ検索で確認した公式URLのHTMLから`og:image`、次に`twitter:image`を最大2候補取得する。AIの取得元根拠を確認できないSNSにはアクセスしない。画像取得の失敗はテキスト結果や公開可否に影響させない。

検索・画像取得・プレビューだけではDBやActive Storage（添付ファイル保存先）を更新しない。ブラウザで編集元と表示用のJPEGを一時保持し、既存の保存操作で画像組と店舗情報を確定する。

## モデル・ライブラリの確認

- 使用中の`openai`は0.80.0。`OpenAI::Models::Responses::WebSearchTool`には画像検索用の専用アクセサーを確認できなかった。これはAPI全体の非対応を意味しない。
- 今回はSDK（API用ライブラリ）やモデルを変更していない。実環境の`gpt-5.6-terra`で、従来のWeb検索と構造化出力に公式画像取得元の確認指示を加えた検索が成功した。
- [OpenAIの画像検索結果仕様](https://developers.openai.com/api/docs/guides/tools-web-search#image-search-results)を利用する経路は今回実装していない。現在のモデル・SDKでその画像検索オプションが利用できるかは未検証。

## 取得・表示の暫定ルール

| 項目 | 試作の扱い |
| --- | --- |
| 取得元 | 公式サイト → X → Instagram → TikTok → YouTube |
| 同一サイト内 | ページ作者が指定した`og:image` → `twitter:image`。任意の画像一覧や最新投稿を巡回しない |
| 同一店舗 | AIの同一店舗判定に加え、公式根拠のURLを実際のWeb検索情報源に照合。店舗・支店ページを企業トップへ広げない |
| SNSの再確認 | HTMLの`og:url`またはcanonical（正規ページURL）が同じアカウント・対象ページを指すことを確認し、ログイン画面などの汎用画像を除外 |
| 最低寸法 | 幅320px・高さ168px。小さすぎるプロフィール画像等を除外 |
| 最大寸法 | 長辺8192px、3200万画素、縦横比8:1以内 |
| 形式・容量 | JPEG / PNG / WebPの静止画像。実体とデコードを検証し、5MiB以下 |
| 切り抜き | 中央を1200×630。利用者が構図を調整可能 |
| 再検索 | 設定済み・手動選択済み・仮反映済み画像は保護。削除・取消後も同じ画面内で自動再取得しない |
| 取得失敗 | 上位の取得元から順に次へ進み、全件失敗なら画像なしで続行 |

最低寸法や代表画像優先は検証可能な暫定ルール。外観・店内写真の意味判定、ロゴと人物写真の優先、動画サムネイルの採用は自動判定していない。

## 実取得の記録

開発環境で既存のAI設定を使い、DBに店舗を作らず確認した。処理時間は単発の実測であり、取得率や待ち時間の保証ではない。ダウンロード画像をリポジトリへ保存・公開していない。

| 確認対象 | 結果 | 時間・補足 |
| --- | --- | --- |
| 秋葉原ディアステージ：AI検索 | テキスト一部取得・公式の[ご案内ページ](https://dearstage.com/about/)を画像取得元として確認 | AI 18.062秒、問い合わせ1回 |
| 同ページの代表画像 | 寸法不足で除外し、画像なしで終了 | 画像取得・検査0.955秒 |
| ROKUSAN ANGEL：AI検索 | テキスト一部取得・[公式サイト](https://rokusanangel.jp/)を確認 | AI 16.667秒、問い合わせ1回 |
| 同サイトの代表画像 | 404,476 bytesの画像を取得・検査できた | 画像取得・検査0.540秒 |
| 公式サイトからリンクされる[Xアカウント](https://x.com/burlesque_rpg)の補助確認 | 最初のプロフィール画像は200×200で除外、次の`twitter:image`のヘッダー画像を取得できた | 1.841秒。画像メタデータのアカウント名と正規URLも一致 |
| 公式サイトからリンクされる[Instagramアカウント](https://www.instagram.com/burlesque.tokyo/)の補助確認 | 候補画像の寸法不足で除外 | 0.572秒 |
| TikTok | 同一店舗の公式アカウントを今回のAI応答から確認できず、実画像の取得は未確認 | 検索ツールからの確認もrobots.txtにより不可。ログインや制限の回避は行っていない |
| YouTube | 同一店舗の公式チャンネル・動画を今回のAI応答から確認できず、実画像の取得は未確認 | 第三者の撮影動画を候補に採用しない |

X・Instagramの補助確認は、公式サイトの実リンクを確認したうえで取得処理単体に渡した。今回の2回のAI応答が返した検証済み画像取得元は公式サイトのみだったため、AI検索からSNSまで一貫して取得できた実例とは区別する。

## 時間と外部アクセスの境界

- AI通信は既存の45秒上限、ブラウザ待ちは50秒。画像取得は別リクエストで全体15秒・取得元ごと3秒、ブラウザの画像通信・処理は20秒上限。画像取得分の追加待ち時間が発生する。
- 画像を取得する間も画面操作を禁止する。画像の通信・処理が時間切れになった場合は完成済みテキストを保持してフォームへ進む。
- DNS（ドメインの接続先）で得たすべてのIPを検証し、公開IPへ接続を固定する。内部・予約IP、認証付きURL、通常ポート以外、危険な転送先を拒否する。プロキシやサイトのCookie・認証情報は使わない。
- 取得したページを別のアカウント・ログインページへ転送しない。画像CDN（画像配信先）への転送も毎回検証する。HTMLは1MiB、転送は最大2回。
- 5分間有効のトークンを店舗と利用者に結び付け、画像取得時にも初回登録セッションと管理権限を確認する。トークンやフォーム値をログへ出さない。
- 画像取得にも別途、利用者ごとに10分間10回の上限を設ける。既存AIの回数制限とは別なので1操作を二重に数えない。

## 外部仕様と本実装に残る確認

- [Open Graph仕様](https://ogp.me/)の`og:image`はページを代表する画像の指定であり、画像の転載・保存許諾を表すものではない。
- [XのoEmbed仕様](https://docs.x.com/x-for-websites/oembed-api)は埋め込みHTMLを返す。今回そのHTMLを実行したり、画像の代わりに埋め込みを表示したりはしていない。
- [TikTokの埋め込み仕様](https://developers.tiktok.com/docs/en/embed-videos)には動画のサムネイル情報があるが、公式動画の特定・利用条件を含めた接続は未実装。
- [YouTubeのチャンネル情報](https://developers.google.com/youtube/v3/docs/channels)にはサムネイル情報があるが、YouTube APIの認証・チャンネル特定は今回追加していない。
- Instagramの最新公式埋め込みドキュメントは今回の調査ツールから取得できず、認証条件を断定していない。
- 公式ページ由来でも転載権限を自動判定できない。公開運用での利用条件、SNS画像を保存・切り抜きして掲載する条件は個別に確認する必要がある。
- SNS取得率を上げる場合は、公式サイト内のSNSリンクを根拠として扱う追加設計や、サービスごとの公式API対応を別途検討する。公式アカウントと確認できないURLまで今回の判定を緩めない。

## 確認コマンド

自動テストは外部通信を代替応答にし、実取得確認と分ける。

```sh
docker compose exec -T app bin/rails test test/services/stores/ai_autofill test/integration/admin/store_ai_autofills_test.rb test/integration/admin/store_registration_setup_test.rb test/services/image_attachments/pair_validator_test.rb test/integration/image_attachment_editor_partial_test.rb test/integration/image_upload_ui_test.rb
npm run test:js
node --test test/javascript/browser/image_attachment_editor_test.cjs
npx playwright test --config=playwright.config.js --project=chromium tests/manual_capture/initial_store_setup.spec.js
npm run build:css
git diff --check
```

実取得の確認用スクリプトは次のとおり。**1回につき有料AI問い合わせ1回**を行い、その応答で確認できた各公式ページを調べる。画像や店舗情報の永続保存は行わない。本番環境では実行を拒否する。

```sh
docker compose exec -T app bin/rails runner script/probe_store_ai_images.rb 'ROKUSAN ANGEL'
```

検証済み画像取得元が空の場合も正常な調査結果とする。取得元と処理時間、成否・除外理由を出力し、取得できなかったサービスを対応済みとして扱わない。
