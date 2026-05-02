# Live Streaming Client 設計

## 1. 概要

ライブ配信クライアントは Amazon IVS Stage を利用する。
キャスト側は publisher、視聴者側は viewer として参加する。

---

## 2. 主要Controller

```text
ivs_publisher_controller
ivs_viewer_controller
```

publisher は機能が多いため、以下の補助モジュールに分割されている。

```text
ivs_publisher/api_client
ivs_publisher/away_canvas
ivs_publisher/banuba_session
ivs_publisher/deepar_session
ivs_publisher/errors
ivs_publisher/media_state
ivs_publisher/ui_state
ivs_publisher/beauty_providers/banuba_provider
ivs_publisher/beauty_providers/deepar_provider
```

---

## 3. Publisher 側

### 3.1 主な責務

- participant token 取得
- IVS Stage join
- camera / mic track 取得
- beauty provider 起動
- publish track 管理
- カメラON/OFF
- マイクON/OFF
- away canvas 切替
- 配信開始時刻通知
- 配信終了API呼び出し
- UI状態同期

---

## 4. Viewer 側

### 4.1 主な責務

- participant token 取得
- IVS Stage join
- subscribe only strategy
- remote track を video element へ接続
- mute状態の復元
- 配信終了イベント時の停止

### 4.2 初期状態

viewer は表示されたら自動で start を試みる。
初期状態では muted preference を復元する。

---

## 5. IVS参加戦略

### Publisher

```text
stageStreamsToPublish: video/audio
shouldPublishParticipant: true
shouldSubscribeToParticipant: 必要に応じて
```

### Viewer

```text
stageStreamsToPublish: []
shouldPublishParticipant: false
shouldSubscribeToParticipant: AUDIO_VIDEO
```

---

## 6. Beauty Provider 抽象化

美顔・エフェクト処理は provider interface で抽象化されている。

共通interface:

```text
start()
ensurePublishTrack()
stop()
applyEffect()
updateBeauty()
ensureInitialBeautyStateLoaded()
videoTrack
stageStream
sourceName
```

実装:

```text
BanubaProvider
DeepARProvider
```

この設計により、IVS publish pipeline 側は provider 差分を意識しにくい。

---

## 7. DeepAR / Banuba

### BanubaProvider

- Banuba player 起動
- beauty config 適用
- effect 適用
- publish track 生成

### DeepARProvider

- DeepAR 起動
- DeepAR effect 適用
- beauty config 適用
- publish track 生成

---

## 8. Away Canvas

away 状態ではカメラ映像ではなく Canvas を publish する設計である。
away_canvas module が canvas解像度同期と描画ループを担当する。

---

## 9. Media State 管理

media_state module が以下を担当する。

- camera media cleanup
- audio track 確保
- camera video track 確保
- canvas publish track 確保
- stage cleanup
- media/canvas cleanup

---

## 10. Error Handling

errors module でエラー表示・人間向けメッセージ化を行う。
SDK未ロード、権限拒否、デバイス取得失敗などをUIへ反映する。

---

## 11. Turboとの相性

Turbo遷移・キャッシュ時に配信SDKやmedia trackが残らないよう、disconnect / before-cache cleanup が重要である。

---

## 12. 設計上の注意点

- publisher controller は責務が多いため、今後もmodule分割を維持する
- provider interface は今後のエフェクトSDK差し替えに重要
- viewer はRails側の joinable=false を正として停止する
- auto resume 機能があるため、入室時の状態同期に注意する
