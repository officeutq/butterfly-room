# Uploads / Assets 設計

## 1. 概要

本アプリでは、プロフィール画像・ブース画像・店舗画像などの画像アップロードに FilePond を利用する。
アップロード前にクライアントサイドでリサイズ・JPEG変換を行う。

---

## 2. 対象Controller

```text
image_upload_controller
filepond_verification_controller
```

---

## 3. image_upload_controller 仕様

### 3.1 入力

targets:

```text
input
removeFlag
```

values:

```text
initialUrl
width
height
```

### 3.2 FilePond設定

```text
allowMultiple: false
allowImagePreview: true
allowImageResize: true
allowImageTransform: true
allowProcess: false
storeAsFile: true
```

### 3.3 リサイズ

```text
target width: value または 1024
target height: value または 1024
mode: contain
upscale: false
```

### 3.4 変換

```text
mime type: image/jpeg
quality: 94
background: #ffffff
```

### 3.5 対応形式

```text
image/jpeg
image/png
image/webp
image/heic
image/heif
```

---

## 4. 削除フラグ

既存画像がある場合、FilePondからファイルを削除すると removeFlag を `1` にする。
新規選択またはファイルが残っている場合は `0` に戻す。

---

## 5. 初期画像

initialUrl がある場合は FilePond に既存画像を追加する。
読み込み失敗時は無視する。

---

## 6. Plugin登録

FilePond plugin は `window.__filepondRegistered` で二重登録を防止する。

利用plugin:

```text
FilePondPluginImagePreview
FilePondPluginImageResize
FilePondPluginImageTransform
```

---

## 7. 設計上の注意点

- FilePondのロードが遅れる可能性があるため、最大40回まで50ms間隔で初期化をリトライする
- allowProcess: false のため、Railsフォーム送信時にファイルとして送る
- HEIC/HEIF変換はブラウザ・FilePond plugin の対応状況に依存する
- サーバー側でもcontent_type validationを必ず行う
