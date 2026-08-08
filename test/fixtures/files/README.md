# 画像正規化テスト用fixture

`sample.heic`、`sample.jpg`、`sample.png`、`sample.webp`、`sample.gif`、`oriented.jpg` は、Pillow / pillow-heif でプログラム生成した小さな画像である。利用者がアップロードした画像や本番S3の画像は含まない。

- `sample.*`: 48x32px の単色またはグラデーション画像
- `oriented.jpg`: EXIF orientation 6を持つ40x20pxの画像
- `corrupt.heic`: 破損画像を再現するための意図的なテキストファイル

これらは `ImageAttachments::NormalizeService` の実体形式判定、JPEG変換、向き補正、透過背景合成、失敗時処理のテストにだけ利用する。
