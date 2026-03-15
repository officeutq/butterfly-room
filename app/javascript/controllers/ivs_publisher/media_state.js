import { destroyBanubaPlayer, stopBanubaSurfaceMediaStreams } from "controllers/ivs_publisher/banuba_session"
import { startCanvasRenderLoop, stopCanvasRenderLoop, syncCanvasResolutionToMeasured } from "controllers/ivs_publisher/away_canvas"

export async function ensureCameraVideoTrack(ctx) {
  if (ctx._cameraVideoTrack) return

  const videoConstraints = ctx._buildCameraVideoConstraints()

  ctx._cameraMedia = await navigator.mediaDevices.getUserMedia({
    video: videoConstraints,
    audio: false,
  })

  ctx._cameraVideoTrack = ctx._cameraMedia.getVideoTracks()[0] || null

  ctx._captureMeasuredVideoTrack(ctx._cameraVideoTrack)
  syncCanvasResolutionToMeasured(ctx)
}

export async function ensureAudioTrack(ctx) {
  if (ctx._audioTrack) return

  ctx._audioMedia = await navigator.mediaDevices.getUserMedia({
    video: false,
    audio: true,
  })

  ctx._audioTrack = ctx._audioMedia.getAudioTracks()[0] || null
}

export function ensureCanvasPublishTrack(ctx) {
  syncCanvasResolutionToMeasured(ctx)
  startCanvasRenderLoop(ctx)

  if (ctx._canvasVideoTrack && ctx._canvasStageStream) return

  const stream = ctx.canvasTarget.captureStream(30)
  const track = stream.getVideoTracks()[0] || null

  ctx._canvasStream = stream
  ctx._canvasVideoTrack = track

  const { LocalStageStream } = window.IVSBroadcastClient || {}
  ctx._canvasStageStream = (track && LocalStageStream) ? new LocalStageStream(track) : null
}

export function cleanupStage(ctx) {
  ctx._stage = null
  ctx._strategy = null
  ctx._banubaStageStream = null
  ctx._canvasStageStream = null
  ctx._audioStageStream = null
  ctx._currentVideoStageStream = null
}

export function cleanupBanubaPublishTrack(ctx) {
  if (ctx._banubaStream) {
    try {
      ctx._banubaStream.getTracks().forEach((t) => t.stop())
    } catch (_) {}
    ctx._banubaStream = null
  }

  ctx._banubaVideoTrack = null
  ctx._banubaStageStream = null
  ctx._publishedVideoTrack = null
  if (ctx._publishedVideoSource === "banuba") {
    ctx._publishedVideoSource = null
  }
}

export function cleanupCameraMedia(ctx) {
  if (ctx._cameraMedia) {
    try {
      ctx._cameraMedia.getTracks().forEach((t) => t.stop())
    } catch (_) {}
    ctx._cameraMedia = null
  }

  ctx._cameraVideoTrack = null
}

export async function cleanupMediaAndCanvas(ctx) {
  stopCanvasRenderLoop(ctx)
  stopBanubaSurfaceMediaStreams(ctx)

  if (ctx._audioMedia) {
    ctx._audioMedia.getTracks().forEach((t) => t.stop())
    ctx._audioMedia = null
  }

  if (ctx._canvasStream) {
    try {
      ctx._canvasStream.getTracks().forEach((t) => t.stop())
    } catch (_) {}
    ctx._canvasStream = null
  }

  cleanupBanubaPublishTrack(ctx)
  await destroyBanubaPlayer(ctx)
  cleanupCameraMedia(ctx)

  ctx._audioTrack = null
  ctx._canvasVideoTrack = null
  ctx._publishedVideoTrack = null
  ctx._publishedVideoSource = null
  ctx._previewOnly = false
  ctx._switchingVideoSource = false
}
