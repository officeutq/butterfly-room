export function clearError(ctx) {
  if (!ctx.hasErrorTarget) return

  if (ctx.hasErrorMessageTarget) {
    ctx.errorMessageTarget.textContent = ""
  } else {
    ctx.errorTarget.textContent = ""
  }

  ctx.errorTarget.classList.add("d-none")
}

export function setError(ctx, msg) {
  if (!ctx.hasErrorTarget) return

  if (ctx.hasErrorMessageTarget) {
    ctx.errorMessageTarget.textContent = msg
  } else {
    ctx.errorTarget.textContent = msg
  }

  ctx.errorTarget.classList.remove("d-none")
}

export function humanizeError(err) {
  const msg = `${err?.message || err}`

  if (msg.includes("token_api_failed(403)")) {
    return "このブースの配信者ではありません（担当キャストのみ配信できます）。"
  }
  if (msg.includes("token_api_failed(409) stage_not_bound")) {
    return "ステージが未準備です（stage_not_bound）。"
  }
  if (msg.includes("token_api_failed(409) not_joinable")) {
    return "まだ配信開始できない状態です（not_joinable：スタンバイ/配信状態を確認）。"
  }
  if (msg.includes("stage_refresh_strategy_not_supported")) {
    return "この環境では映像切替に未対応です。"
  }
  if (msg.includes("canvas_publish_track_unavailable")) {
    return "席外し映像の準備に失敗しました。もう一度お試しください。"
  }
  if (msg.includes("banuba_publish_track_unavailable")) {
    return "Banuba の映像出力取得に失敗しました。もう一度お試しください。"
  }
  if (msg.includes("banuba_render_node_not_found")) {
    return "Banuba の描画面が見つかりませんでした。再読込してください。"
  }
  if (msg.includes("banuba_client_token_missing")) {
    return "Banuba の client token が未設定です。"
  }
  if (msg.includes("banuba_surface_missing")) {
    return "Banuba の表示領域が見つかりません。"
  }
  if (msg.includes("not loaded")) {
    return "IVS SDK の読み込みに失敗しました（script tag を確認してください）。"
  }

  if (err?.name === "NotAllowedError" || err?.name === "SecurityError") {
    return "カメラ/マイク権限が拒否されました。ブラウザ設定で許可してください。"
  }
  if (err?.name === "NotFoundError" || err?.name === "OverconstrainedError") {
    return "利用できるカメラ/マイクが見つかりません。接続やOS設定を確認してください。"
  }
  if (err?.name === "NotReadableError") {
    return "カメラ/マイクを使用できません（他アプリ使用中の可能性）。"
  }

  return `配信開始に失敗しました: ${msg}`
}
