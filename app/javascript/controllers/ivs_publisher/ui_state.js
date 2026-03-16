import { setError } from "controllers/ivs_publisher/errors"
import { startCanvasRenderLoop, stopCanvasRenderLoop, syncCanvasResolutionToMeasured } from "controllers/ivs_publisher/away_canvas"

export function syncMicUI(ctx) {
  if (!ctx.hasMicBtnTarget || !ctx.hasMicIconTarget) return

  ctx.micBtnTarget.disabled = !ctx._broadcasting
  ctx.micBtnTarget.classList.toggle("is-off", !ctx._micEnabled)
  ctx.micBtnTarget.setAttribute(
    "aria-label",
    ctx._micEnabled ? "マイクをオフにする" : "マイクをオンにする"
  )
  ctx.micBtnTarget.setAttribute(
    "title",
    ctx._micEnabled ? "マイクON" : "マイクOFF"
  )

  ctx.micIconTarget.className = ctx._micEnabled
    ? "bi bi-mic-fill"
    : "bi bi-mic-mute-fill"
}

export function applyAwayMode(ctx) {
  if (ctx.hasBanubaSurfaceTarget) ctx.banubaSurfaceTarget.classList.add("d-none")
  if (ctx.hasCanvasTarget) ctx.canvasTarget.classList.remove("d-none")

  syncCanvasResolutionToMeasured(ctx)
  startCanvasRenderLoop(ctx)

  if (ctx._broadcasting && ctx._publishedVideoSource !== "canvas" && !ctx._switchingVideoSource) {
    setError(ctx, "映像状態の同期が必要です。もう一度お試しください。")
  }
  console.log("away canvas size", {
    measured: ctx._measuredVideo,
    canvasWidth: ctx.canvasTarget?.width,
    canvasHeight: ctx.canvasTarget?.height,
  })
}

export function applyNormalMode(ctx) {
  if (ctx.hasCanvasTarget) ctx.canvasTarget.classList.add("d-none")
  if (ctx.hasBanubaSurfaceTarget) ctx.banubaSurfaceTarget.classList.remove("d-none")

  if (!ctx._broadcasting && ctx._publishedVideoSource !== "canvas") {
    stopCanvasRenderLoop(ctx)
  }

  if (ctx._broadcasting && ctx._publishedVideoSource !== "banuba" && !ctx._switchingVideoSource) {
    setError(ctx, "映像状態の同期が必要です。もう一度お試しください。")
  }
}

export function applyCurrentMode(ctx) {
  if (ctx._mode === "away") {
    applyAwayMode(ctx)
  } else {
    applyNormalMode(ctx)
  }
}

export function syncUI(ctx) {
  if (ctx.hasStartBtnTarget && ctx.hasEndBtnTarget) {
    if (ctx._broadcasting) {
      ctx.startBtnTarget.classList.add("d-none")
      ctx.endBtnTarget.classList.remove("d-none")
    } else {
      ctx.startBtnTarget.classList.remove("d-none")
      ctx.endBtnTarget.classList.add("d-none")
    }
  }

  const canToggleCamera = ctx._broadcasting && !ctx._switchingVideoSource

  if (ctx.hasCameraOffBtnTarget) {
    ctx.cameraOffBtnTarget.disabled = !canToggleCamera || ctx._boothStatus === "away"
    ctx.cameraOffBtnTarget.classList.toggle("d-none", ctx._boothStatus === "away")
  }

  if (ctx.hasCameraOnBtnTarget) {
    ctx.cameraOnBtnTarget.disabled = !canToggleCamera || ctx._boothStatus !== "away"
    ctx.cameraOnBtnTarget.classList.toggle("d-none", ctx._boothStatus !== "away")
  }

  syncMicUI(ctx)

  if (ctx.hasSummaryPanelTarget) {
    const visible = (ctx._boothStatus === "standby") && !ctx._broadcasting
    ctx.summaryPanelTarget.classList.toggle("d-none", !visible)
  }

  if (ctx.hasStartBtnTarget) {
    const normal = ctx.startBtnTarget.dataset.labelNormal || "配信開始"
    const resume = ctx.startBtnTarget.dataset.labelResume || "配信に戻る"
    ctx.startBtnTarget.textContent = ctx._resumable ? resume : normal
  }

  if (ctx.hasMetaPanelTarget) {
    const visible =
      ctx._boothStatus === "standby" ||
      ctx._boothStatus === "live" ||
      ctx._boothStatus === "away" ||
      ctx._broadcasting

    ctx.metaPanelTarget.classList.toggle("d-none", !visible)
  }

  if (ctx.hasDrinkPanelTarget) {
    const visible =
      ctx._broadcasting ||
      ctx._boothStatus === "live" ||
      ctx._boothStatus === "away"

    ctx.drinkPanelTarget.classList.toggle("d-none", !visible)
  }

  if (ctx.hasOpsPanelTarget) {
    const visible = ctx._broadcasting
    ctx.opsPanelTarget.classList.toggle("d-none", !visible)
  }
}
