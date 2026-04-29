function applyDeepARPreviewNodeStyles(node) {
  if (!node || !node.style) return

  node.style.position = "absolute"
  node.style.inset = "0"
  node.style.width = "100%"
  node.style.height = "100%"
  node.style.maxWidth = "100%"
  node.style.maxHeight = "100%"
  node.style.objectFit = "contain"
  node.style.display = "block"
}

async function syncDeepARRenderedNode(ctx, node) {
  if (!node) return

  applyDeepARPreviewNodeStyles(node)

  if (typeof ctx._captureMeasuredBanubaNode === "function") {
    ctx._captureMeasuredBanubaNode(node)
  }

  await ctx._nextFrame()

  applyDeepARPreviewNodeStyles(node)

  if (typeof ctx._captureMeasuredBanubaNode === "function") {
    ctx._captureMeasuredBanubaNode(node)
  }

  await ctx._nextFrame()

  applyDeepARPreviewNodeStyles(node)

  if (typeof ctx._captureMeasuredBanubaNode === "function") {
    ctx._captureMeasuredBanubaNode(node)
  }
}

async function buildDeepARInputVideo(ctx) {
  await ctx._ensureCameraVideoTrack()

  const rawCameraStream = new window.MediaStream()

  if (ctx._cameraVideoTrack) {
    rawCameraStream.addTrack(ctx._cameraVideoTrack)
  }

  const video = document.createElement("video")
  video.autoplay = true
  video.muted = true
  video.playsInline = true
  video.srcObject = rawCameraStream

  await video.play()

  ctx._deepARInputVideo = video
  ctx._deepARInputStream = rawCameraStream

  return video
}

export async function waitForDeepARRenderedNode(ctx) {
  const timeoutMs = 5000
  const startAt = Date.now()

  while ((Date.now() - startAt) < timeoutMs) {
    const node =
      ctx._deepAR?.canvas ||
      ctx.banubaSurfaceTarget?.querySelector("canvas, video")

    if (node && typeof node.captureStream === "function") {
      return node
    }

    await ctx._nextFrame()
  }

  throw new Error("deepar_render_node_not_found")
}

export async function ensureDeepARStarted(ctx) {
  if (ctx._deepARStarted && ctx._deepAR) return

  if (!ctx.deeparLicenseKeyValue) {
    throw new Error("deepar_license_key_missing")
  }

  if (!window.deepar || typeof window.deepar.initialize !== "function") {
    throw new Error("deepar_sdk_not_loaded")
  }

  if (!ctx.hasBanubaSurfaceTarget) {
    throw new Error("deepar_surface_missing")
  }

  const inputVideo = await buildDeepARInputVideo(ctx)
  const effect = ctx.deeparDefaultEffectUrlValue || ""

  const deepAR = await window.deepar.initialize({
    licenseKey: ctx.deeparLicenseKeyValue,
    previewElement: ctx.banubaSurfaceTarget,
    effect,
    rootPath: ctx.deeparRootPathValue || "/deepar",
    cameraConfig: {
      disableDefaultCamera: true,
    },
  })

  if (typeof deepAR.setVideoElement !== "function") {
    throw new Error("deepar_set_video_element_not_available")
  }

  deepAR.setVideoElement(inputVideo, false)

  ctx._deepAR = deepAR
  ctx._deepARStarted = true

  ctx._deepARRenderedNode = await waitForDeepARRenderedNode(ctx)
  await syncDeepARRenderedNode(ctx, ctx._deepARRenderedNode)

  if (typeof ctx._syncCanvasResolutionToMeasured === "function") {
    ctx._syncCanvasResolutionToMeasured()
  }
}

export async function ensureDeepARPublishTrack(ctx) {
  await ensureDeepARStarted(ctx)

  if (ctx._deepARVideoTrack && ctx._deepARStageStream) return

  const renderedNode = ctx._deepARRenderedNode || await waitForDeepARRenderedNode(ctx)
  ctx._deepARRenderedNode = renderedNode

  await syncDeepARRenderedNode(ctx, renderedNode)

  if (typeof ctx._syncCanvasResolutionToMeasured === "function") {
    ctx._syncCanvasResolutionToMeasured()
  }

  const stream = renderedNode.captureStream(30)
  const track = stream.getVideoTracks()[0] || null

  if (!track) {
    throw new Error("deepar_publish_track_unavailable")
  }

  ctx._deepARStream = stream
  ctx._deepARVideoTrack = track

  const { LocalStageStream } = window.IVSBroadcastClient || {}
  ctx._deepARStageStream = track && LocalStageStream ? new LocalStageStream(track) : null
}

export async function destroyDeepAR(ctx) {
  if (ctx._deepARStream) {
    try {
      ctx._deepARStream.getTracks().forEach((track) => track.stop())
    } catch (_) {}
  }

  ctx._deepARStream = null
  ctx._deepARVideoTrack = null
  ctx._deepARStageStream = null
  ctx._deepARRenderedNode = null

  if (ctx._deepARInputVideo) {
    try {
      ctx._deepARInputVideo.pause()
    } catch (_) {}

    try {
      ctx._deepARInputVideo.srcObject = null
    } catch (_) {}
  }

  ctx._deepARInputVideo = null

  if (ctx._deepARInputStream) {
    try {
      ctx._deepARInputStream.getTracks().forEach((track) => track.stop())
    } catch (_) {}
  }

  ctx._deepARInputStream = null

  if (ctx._deepAR && typeof ctx._deepAR.shutdown === "function") {
    try {
      ctx._deepAR.shutdown()
    } catch (_) {}
  }

  ctx._deepAR = null
  ctx._deepARStarted = false

  if (ctx.hasBanubaSurfaceTarget) {
    ctx.banubaSurfaceTarget.innerHTML = ""
  }
}

export async function applyDeepAREffect(ctx, effect = null) {
  if (!ctx._deepAR) return

  const selectedEffect = ctx._selectedEffect || "deepar_aviators"

  if (selectedEffect === "none") {
    if (typeof ctx._deepAR.clearEffect === "function") {
      await ctx._deepAR.clearEffect()
      return
    }

    if (typeof ctx._deepAR.switchEffect === "function") {
      await ctx._deepAR.switchEffect("")
      return
    }

    throw new Error("deepar_clear_effect_not_available")
  }

  let effectUrl = ""

  if (selectedEffect === "deepar_aviators") {
    effectUrl = ctx.deeparDefaultEffectUrlValue || ""
  } else {
    effectUrl =
      effect?.url ||
      effect?.effectUrl ||
      ""
  }

  if (!effectUrl) {
    throw new Error(`deepar_effect_url_missing(${selectedEffect})`)
  }

  if (typeof ctx._deepAR.switchEffect !== "function") {
    throw new Error("deepar_switch_effect_not_available")
  }

  await ctx._deepAR.switchEffect(effectUrl)
}

export function ensureInitialDeepARBeautyStateLoaded() {
  return Promise.resolve({})
}

export function applyDeepARBeautyConfig() {
  return Promise.resolve()
}
