# HEIC / HEIFブラウザ変換の検証（#1131）

更新: 2026-09-03。親Epic #1128 / 大Epic #1127。

本書は**保存を伴わない検証実装**の記録。iPhoneの12MP実撮影HEICはユーザー報告で変換成功を確認したが、24MP・実機操作の網羅確認・Android Chrome・本番採用判断は未完了である。本番のFilePond・Active Storage・`ImageAttachments::UpdateService` は変更しない。

## ライブラリ比較と暫定選定

2026-09-03に公式npmメタデータ、公開パッケージ、ソースを確認した。更新日はnpmの `time.modified` であり、リポジトリの最終コミット日ではない。容量は非圧縮byte / gzip byte（Nodeの既定gzip設定による計測）。展開サイズと実際に読み込むファイルを区別する。

| 候補 | npm更新日 / 展開サイズ | 比較した配信ファイルの容量 | 判断 |
| --- | --- | --- | --- |
| heic-to 1.5.2 | 2026-05-26 / 24,357,392 | CSP対応decoder: 3,160,699 / 753,858 | libheif 1.22.2・libde265 1.0.16。今回の検証候補 |
| heic2any 0.0.4 | 2023-03-29 / 2,719,022 | dist/heic2any.min.js: 1,351,840 / 340,226 | wrapperはMITだが内包decoderのLGPLは別。古い配布・非公開の共有Workerに依存するため今回は不採用 |
| libheif-js 1.19.8 | 2025-06-12 / 6,398,400 | libheif/libheif.js: 2,178,016 / 543,047 | LGPL-3.0。低水準APIで構成可能だが、上記より古いlibheif。今回の実機評価は新しい版で先行 |

heic-toは **1.5.2を完全固定**。高水準の `heicTo` / `heic-to/next` は内部Workerを呼出側から破棄できず、画素展開前の上限判定も挟めないため、そのまま使わない。パッケージ内の無改変 `src/lib/libheif-without-unsafe-eval.js` を、アプリ側で所有する独立したmodule Worker（モジュール形式の別スレッド）から読み込む。

これはパッケージの内部パスと低水準APIを使う**検証用アダプター**で、長期互換性の保証はない。更新時はパス、解放API、画素展開前の寸法判定、CSP、回転・透過・複数画像テストを再確認する。本番では同版の独立decoder配布を続けるかも含め#1134で決める。`libheif-js` 系の直接採用も代替候補として残す。

一次資料:

- [heic-to 1.5.2のREADMEとビルド手順](https://github.com/hoppergee/heic-to/tree/v1.5.2)
- [heic-toのライセンス](https://github.com/hoppergee/heic-to/blob/v1.5.2/LICENSE)
- [heic2anyの公式リポジトリ](https://github.com/alexcorvi/heic2any)
- [libheif-jsの公式リポジトリ](https://github.com/catdad-experiments/libheif-js)
- [libheif 1.22.2](https://github.com/strukturag/libheif/tree/v1.22.2)、[libde265 1.0.16](https://github.com/strukturag/libde265/tree/v1.0.16)

### ライセンス・配信

heic-toのnpm表記はLGPL-3.0、LICENSE本文は**LGPL version 3 or later**。MITとして扱わない。含まれるlibheif/libde265もLGPLである。

- 無改変decoderをアプリ本体と結合せず、独立モジュールとして自サイトから配信する
- 検証画面から `/licenses/heic-verification.txt` へリンクし、LGPL/GPL本文、対応する版のソース・ビルド手順を提示する
- 配布時のソース提供・再リンク/置換・利用条件・特許等を含む最終的な採用可否は別途確認する。検証実装やリンク設置だけで法的適合を保証しない
- npm auditでは既存の `immutable` / `nanoid` / `picomatch` にhigh 3件を検出した。今回追加したheic-toのnpm依存は0件で、これらの更新は本Issueで行わない。ネイティブdecoder全体の安全性を保証する監査でもない

## 処理経路とリソース解放

1. 軽量な `heic_converter.js` が容量と先頭4096byte以内の `ftyp` を検査。HEIC / HEIFのmajor/compatible brandを見て判別する。拡張子・MIMEだけでは実体と認めず、AVIF / AVISは除外する
2. HEIC選択時だけ同一origin（配信元）のWorkerを起動し、入力ArrayBufferを転送。通常のJPEG / PNG / WebPではWorker・decoderを読み込まない
3. decoderがコンテナを解析して画像ハンドルを取得。**先頭画像の寸法を検査してから**HEVC画素を展開する。代表画像が2番目でも先頭を使い、動画・個別画像選択は扱わない
4. libheifが反映した向きのRGBA（展開後の画素データ）をsRGB Canvasへ置き、白背景を合成。未クロップのフルサイズJPEGを品質0.94で生成する。手動の二重回転はしない。入力のEXIF/GPSをコピーしない
5. そのJPEGを既存 `normalizeEditingSource` に渡し、用途別最低寸法・編集元上限・品質を適用。その出力だけをCropper.jsへ渡す。変換中間JPEGの品質は0.94固定、画面の品質選択は最終編集元の品質
6. 成功・失敗・中止・時間切れでWorkerをterminateし、画像ハンドルとデコード画像・コンテキスト・一時Canvasを解放。中止・画像差し替え・Turbo cache前・disconnectでは古い結果を反映しない

WorkerでOffscreenCanvas（画面外の描画領域）が使えない場合、**HEICのデコードはWorker内のまま**行い、RGBAを転送して画面側のCanvasでJPEGだけ生成する。Windows WebKitでこの経路を確認。`jpegEncoder` で実行経路を区別する。Workerからメイン処理への黙ったデコード切替や、未変換HEICをCropperへ渡す処理はない。

メインスレッド比較は明示選択時のみ、400万画素に制限する。同期デコード中は画面操作や中止が遅れ、強制時間切れもできない。Workerモードでも画面側のJPEG生成・後続の正規化は即時中断できず、完了後に結果を破棄する。連続処理は既存の直列化と世代番号で競合を防ぐ。

### CSPとRails配信

既存のグローバルCSP設定は変更していない。独立ブラウザテストでは `script-src 'self'`（テスト起動用nonce併用）・`worker-src 'self'` の制限下で実行し、`unsafe-eval` / `wasm-unsafe-eval` / `worker-src blob:` なしで通過した。Blob画像の表示は別に `img-src blob:` が必要。テスト中の出力画像取得にのみ `connect-src blob:` を使用する。

Railsの `asset_path` でWorkerとdecoderのdigest付きURLを渡す。`node_modules` は既存のasset pathに入っており、追加のCDNやimportmapへの重いdecoderの静的pinは不要。通常のimportmapに含まれる軽量な判定モジュールとは区別する。

Dockerでは `node_modules` が専用volumeのため、初回は次を実行する（ホスト側だけのnpm installでは不足する）。

```bash
docker compose exec -T app npm install --ignore-scripts
```

ローカル開発環境でWorkerとdecoderのdigest付きURLがHTTP 200 / text/javascriptで配信されることを確認済み。本番asset precompile・圧縮転送・CDN上のCSPは未確認で、gzip値は実際の転送量を保証しない。

## 暫定上限・失敗時の扱い

| 項目 | 暫定値 |
| --- | --- |
| 入力ファイル | 空でない20MiB以下 |
| Workerの先頭画像・標準 | 1600万画素・長辺8192px・縦横比8:1以下 |
| Workerの先頭画像・大きい写真の比較 | 明示選択時のみ3200万画素まで。辺・比率は標準と同じ |
| メインスレッド比較 | 400万画素以下、辺・比率は同じ |
| コンテナの静止画像 | 20画像以下、展開するのは先頭だけ |
| Worker待ち時間 | 起動・読み込み・デコード・Worker内JPEG生成を含む30秒 |
| 後続の編集元正規化 | #1130の候補設定を継続 |

上限値は実機測定に基づく確定値ではない。HEICの初期画素展開はJPEG入力より保守的に制限した。4800万画素などは後段で縮小する前に拒否する。入力20MiBは、生成JPEGが20MiB以下になる保証ではなく、中間JPEGが後続の入力容量上限に達する場合も失敗とする。容量調整・送信は#1132へ引き継ぐ。

「HEICの入力画素数上限（Worker専用）」で標準16MPと比較32MPを切り替える。24MP写真は実寸5712×4284（約2450万画素）になるため、比較上限は32MPとした。初期表示・再接続は標準へ戻り、自動的な上限引き上げはしない。32MP選択時はメモリ不足・タブ終了の可能性を警告し、メインスレッド選択時はこの設定を無効にして400万画素上限を維持する。

切り替え時は進行中Workerを中止し、最初の入力から再変換してクロップを初期化する。後続の編集元正規化は既定800万画素のまま。`heicConversion.limitMode`（`standard` / `large`）と `heicConversion.pixelLimit` に実行時の設定を記録する。Worker内JPEG生成と、RGBAを画面へ転送する経路の両方で選択上限を適用する。ピークメモリは引き続き未測定であり、上限内の安全性を保証しない。

破損、対応外codec、Worker読込失敗、変換例外、上限超過は状態欄へ表示し、新画像の編集元・表示用リンクを残さない。ファイル再選択で復帰できる。生のHEICやサーバー変換へ切り替えない。上限内でも実端末のメモリ不足・タブ強制終了は防げない。ネイティブ側の検証で完全なファイル安全性を証明するものではない。

## PC自動検証結果

2026-09-03、Windows / PlaywrightのChromium 149.0.7827.55・Firefox 151.0・WebKit 26.5で次を確認した。**Windows WebKitはiPhone Safari実機ではない。**

- HEIC → フルサイズJPEG → 編集元正規化 → 両用途のCropper・JSON復元・JPEG生成
- 96×160へ回転するHEIF、透過HEICの白合成、4領域の色、EXIF非保持
- 複数画像（2番目が代表画像）から先頭のみ利用
- 実Workerの中止・画面離脱相当のcleanup・再接続・再選択
- `ftyp` がある破損HEICと拡張子だけHEICのエラー、未変換利用なし
- 既存JPEG / PNG / WebP正規化と縮小下限・JSON復元の回帰テスト
- 初回だけプレビューの構図がずれる問題を修正。Cropperの `$ready()` がキャッシュ済み画像で描画前に完了する場合に備え、2回のrequestAnimationFrameで初回描画を待ってから選択枠・初回出力を確定する。修正前に失敗・修正後に成功する4色画像の回帰テストを追加
- 単体テストで画素展開前の寸法拒否、画像数上限、RGBA不正、成功・例外時のネイティブ解放、Workerの中止・30秒相当の時間切れ・読み込み/通信エラー時の破棄を確認
- 32MP比較追加後に同じ3ブラウザで再確認。5712×4284の合成HEICを標準で拒否、比較設定で両用途へ変換し、上限の実行値をJSONで確認。変換中の標準への切り替え、中止後の古い画像非表示、正常画像での復帰、再接続時の標準復帰を確認
- 単体テストは72件、Rails統合テストは5件 / 56 assertions成功。32MPの境界と超過、48MP拒否、長辺・比率制限、メイン比較の4MP維持も確認
- ローカルRailsの実Stimulus接続でも、24MPの拒否 → 上限選択だけで再変換 → メイン比較で4MP拒否 → 再読み込みで標準復帰を確認。390px幅で警告表示・横はみ出しなし。PCでの画面幅変更であり、iPhone実機試験の代替ではない

合成画像のWorker測定例（出力byte / 入力読込〜フルサイズJPEG取得の経過ms）:

| 入力 | 入力byte | Chromium | Firefox | WebKit |
| --- | --- | --- | --- | --- |
| 48×32 | 1,172 | 877 / 145.2 | 698 / 337 | 877 / 224 |
| 1200×800 | 4,354 | 7,515 / 225.9 | 28,096 / 372 | 7,515 / 314 |
| 4000×3000 | 17,115 | 79,191 / 644.8 | 351,723 / 727 | 79,191 / 702 |

1200×800のメインスレッド比較はChromium 80ms、Firefox 109ms、WebKit 109ms。先行変換後の再利用可能なモジュール読込等を含み、Workerは毎回起動するため、同じ初期条件の速度比較ではない。表は単発測定・開発PC・一部並列テスト下の参考値。画像は単色領域が多く、実写真の入力容量・負荷・画質を代表しない。

RGBA 1枚分はそれぞれ6,144 / 3,840,000 / 48,000,000byte。decoder内部のヒープ公開値は取得できないため `libraryHeapBytes: null`、全体のピークは `peakBytes: null` としている。RGBA容量を実メモリ使用量とみなさない。ネイティブ画像、入力コピー、Canvas、JPEG、後続正規化もあるため、実ピークは別途測定が必要。

### 再現コマンド

```bash
npm run test:js
node --test test/javascript/browser/heic_conversion_test.cjs
node --test test/javascript/browser/image_upload_verification_zoom_test.cjs
node --test test/javascript/browser/image_source_normalization_test.cjs
docker compose exec -T app bin/rails test test/integration/system_admin_image_upload_verification_test.rb
```

他エンジンは `IMAGE_VERIFICATION_BROWSER=firefox` / `webkit` を設定する（PowerShellは `$env:IMAGE_VERIFICATION_BROWSER='firefox'`）。Playwrightブラウザは既存の導入手順に従う。fixtureの生成手順は `test/fixtures/files/README.md` に記載。ブラウザテストは実ライブラリと実コードを小さなHTTPサーバーで配信するが、Stimulus接続はテスト用に置き換えている。認可・有効化・ダッシュボード導線・asset URLの埋め込みはRails統合テストで確認する。

加えて、ローカルRailsの既存マニュアル用system_adminアカウントでログインし、ダッシュボード導線 → 回転HEIF選択 → 実Stimulus接続 → HEIC変換 → 初回プレビューの4色一致を確認した。1440px/390px幅で横方向のはみ出し・JavaScript例外がないことも確認した。これはPCのウィンドウ幅変更であり、実機のタッチ操作やSafari検証の代替ではない。

## iPhone実機のユーザー報告（2026-09-03）

提供された測定JSONに基づく結果。端末モデルは未確認。User Agent表記は `iPhone OS 18_7` / `Version/26.6.1` であり、OS設定画面での版確認は未実施。写真そのものや元ファイル名は記録しない。

- 写真アプリ上ではHEIFの24MP写真を選択したところ、ページは5712×4284のJPEGを受け取り、`heicConversion: null`。この経路はHEIC変換成功に数えない
- ファイル選択経由では暫定上限超過をユーザーが確認。24MPは16MPを超えるため、32MPの比較設定を追加した
- 12MPで新しく撮影しファイル選択したHEICは、Worker / OffscreenCanvasで4032×3024のフルサイズJPEGへ変換成功。入力1,710,996byte → 中間JPEG3,653,420byte、経過1,184ms
- 後続の編集元JPEGは3265×2449、2,600,832byte、140ms。記録された処理の合計は1,324msで、クロップ画面の描画時間全体を意味しない
- RGBA 1枚分は48,771,072byte。`libraryHeapBytes` / `peakBytes` はnull。実メモリの安全上限、色・向き・タッチ操作・連続差し替えは、このJSONだけで確認済みとしない

### 24MP比較の実機手順

1. ステージングの検証ページを再読み込みし、「HEIC / HEIF・スマホ検証」でWorkerと「大きい写真の比較（3200万画素まで・高負荷）」を選ぶ。編集元の上限設定は既定のままにする
2. HEICのまま「ファイル」に保存した24MP写真を1枚選ぶ。JSONの `heicConversion.limitMode: "large"` / `pixelLimit: 32000000` と実体brandを確認する。`heicConversion: null` ならHEIC変換経路ではない
3. まず1回成功すること、向き・色・指移動・ピンチ・両用途のJPEG生成を確認する。問題がなければ画像を差し替えて3回程度繰り返し、各回の時間・画面停止・勝手な再読み込みの有無を記録する
4. タブ終了、再読み込み、操作不能が起きた場合はその時点で中止し、端末モデル・OS・画像寸法・失敗した回数を記録する。無理に再試行しない。標準16MPへの切り替えで同じ画像が拒否され、小さい画像で復帰することも確認する

PCでの合成画像成功は実写真の負荷を代表しない。単発・数回の成功だけでメモリ安全性を保証せず、24MP対応と上限の本番採用は実機結果を踏まえて別途判断する。

## 実機で残る確認と記録テンプレート

system_adminでダッシュボードの「画像アップロード検証」を開く（`IMAGE_UPLOAD_VERIFICATION_ENABLED=1`）。スマホは自身のlocalhostではなく、端末から到達できる開発/検証環境を利用する。認可や公開範囲を緩める設定は本実装では追加しない。

1. 実際に撮影したHEIC / HEIF（縦・横、可能なら異なるiPhone世代、通常/大きい写真）を選ぶ。測定JSONの `heicConversion` がnullの場合はブラウザへ渡った実体がHEICではなく、HEIC検証済みとは扱わない
2. まずWorkerの既定設定で、向き・色・白背景・細部・変換待ち中の操作を確認。「編集元JPEG」と「表示用JPEG」の両方を取得する
3. JPEG / PNG / WebPでも基準動作を確認し、HEIC変換後も1:1と40:21で指移動・ピンチ・操作ボタン・端での縮小下限・JSON復元・画面回転後の復元を確認する
4. 画像差し替え、ファイル選択のキャンセル、変換中止、ダッシュボード往復を繰り返す。古い画像・動かない画面・時間やメモリの増加を確認する。メイン比較は400万画素以下の画像のみ
5. 破損・上限超過時に編集不能と明確なエラーになること、正常画像を選び直して復帰することを確認する
6. #1131へ下の形式で記録。写真そのものの共有は必須ではなく、ファイル名等の個人情報は測定JSONから伏せてよい

```text
端末 / OS / ブラウザ版:
撮影端末・画像種別（HEIC/HEIF、縦横、HDR等）:
実体brand / 入力寸法・容量:
変換方式 / jpegEncoder / limitMode / pixelLimit:
フルサイズJPEG・編集元JPEGの寸法と容量:
測定JSON（個人情報を伏せる）:
両用途の指移動・ピンチ・縮小下限:
JSON復元・画面回転・JPEG取得:
差し替え・中止・画面往復・連続回数:
向き・色・画質・白背景:
エラー時の表示・復帰:
メモリ実測手法・結果（未測定なら未測定）:
未確認・問題点:
```

未完了: 実撮影画像の世代差、HEIFの対応codec幅、HDR/10bit/広色域/ICCの色と階調、Live Photo由来の実コンテナ、スマホ実機のタッチ操作・回転・保存、メモリ不足/タブ終了、実機の連続変換、配布ライセンスの最終判断。これらを確認するまで#1131をDoneにしない。
