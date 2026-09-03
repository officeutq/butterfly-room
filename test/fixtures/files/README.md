# 画像正規化テスト用fixture

`sample.heic`、`sample.jpg`、`sample.png`、`sample.webp`、`sample.gif`、`oriented.jpg` は、Pillow / libheif でプログラム生成した小さな画像である。利用者がアップロードした画像や本番S3の画像は含まない。`sample.heic` はUbuntu 24.04の `heif-enc` で `sample.png` から生成し、CIのImageMagick 6でも読み取れる形式にしている。

- `sample.*`: 48x32px の単色またはグラデーション画像
- `oriented.jpg`: EXIF orientation 6を持つ40x20pxの画像
- `corrupt.heic`: 破損画像を再現するための意図的なテキストファイル

これらは `ImageAttachments::NormalizeService` および保存を伴わないブラウザ検証の実体形式判定、JPEG変換、向き補正、透過背景合成、失敗時処理のテストにだけ利用する。

## HEICブラウザ検証（#1131）

`heic/` 配下もすべてプログラム生成画像であり、実機撮影画像ではない。

- `medium.heic`: 1200×800、左上赤・右上緑・左下青・右下黄
- `large.heic`: 4000×3000、同じ4色。単色領域が多いため容量は小さく、実写真の圧縮・デコード負荷を代表しない
- `photo-24mp.heic`: 5712×4284（約2450万画素）、同じ4色。16MPで拒否、32MP比較で変換する境界と画面復帰を確認する。実写真の負荷を代表しない
- `rotated.heif`: 160×96にorientation 6を付与。コンテナの回転を反映すると96×160、左上青・右上赤・左下黄・右下緑
- `alpha.heic`: 96×64、左半分透明・右半分赤
- `multiple.heic`: 96×64の赤・青の2画像。2番目がprimary（代表画像）でも方針どおり先頭の赤を利用する

再生成する場合のみ、隔離したPython環境に `Pillow==12.3.0 pillow-heif==1.6.0` を入れて `python test/fixtures/files/heic/generate.py` を実行する。通常のテストにはPython・HEICエンコーダーは不要。生成バージョンや圧縮器が変わるとバイナリは一致しない場合がある。

特定のfixtureだけを生成する場合は `--only photo-24mp.heic` のように指定する。既存fixtureは上書きしない。
