import { Dom, Effect, Module, Player, MediaStream as BanubaMediaStream } from "banuba-web-sdk"

export function normalizedBanubaSdkBaseUrl(ctx) {
  return (ctx.banubaSdkBaseUrlValue || "").replace(/\/+$/, "")
}

export function stopBanubaSurfaceMediaStreams(ctx) {
  if (!ctx.hasBanubaSurfaceTarget) return

  const mediaElements = ctx.banubaSurfaceTarget.querySelectorAll("video, audio")

  mediaElements.forEach((el) => {
    try {
      if (typeof el.pause === "function") {
        el.pause()
      }
    } catch (_) {}

    try {
      const stream = el.srcObject
      if (stream && typeof stream.getTracks === "function") {
        stream.getTracks().forEach((track) => {
          try {
            track.stop()
          } catch (_) {}
        })
      }
      el.srcObject = null
    } catch (_) {}
  })
}

function applyBanubaPreviewNodeStyles(node) {
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

async function syncBanubaRenderedNode(ctx, node) {
  if (!node) return

  applyBanubaPreviewNodeStyles(node)
  ctx._captureMeasuredBanubaNode(node)

  await ctx._nextFrame()

  applyBanubaPreviewNodeStyles(node)
  ctx._captureMeasuredBanubaNode(node)

  await ctx._nextFrame()

  applyBanubaPreviewNodeStyles(node)
  ctx._captureMeasuredBanubaNode(node)
}

function ensureBeautyEffect(ctx) {
  const url = ctx.banubaEffectUrlValue || ""
  if (!url) {
    throw new Error("banuba_beauty_effect_url_missing")
  }

  if (!ctx._banubaEffects) {
    ctx._banubaEffects = {}
  }

  if (!ctx._banubaEffects.beauty) {
    ctx._banubaEffects.beauty = new Effect(url)
  }

  return ctx._banubaEffects.beauty
}

export async function waitForBanubaRenderedNode(ctx) {
  const timeoutMs = 5000
  const startAt = Date.now()

  while ((Date.now() - startAt) < timeoutMs) {
    const node = ctx.banubaSurfaceTarget?.querySelector("canvas, video")
    if (node) return node
    await ctx._nextFrame()
  }

  throw new Error("banuba_render_node_not_found")
}

export async function destroyBanubaPlayer(ctx) {
  stopBanubaSurfaceMediaStreams(ctx)

  if (ctx._banubaPlayer) {
    try {
      if (typeof ctx._banubaPlayer.destroy === "function") {
        await ctx._banubaPlayer.destroy()
      }
    } catch (_) {}
  }

  stopBanubaSurfaceMediaStreams(ctx)

  ctx._banubaPlayer = null
  ctx._banubaStarted = false
  ctx._banubaRenderedNode = null
  ctx._banubaEffects = {}

  if (ctx.hasBanubaSurfaceTarget) {
    ctx.banubaSurfaceTarget.innerHTML = ""
  }
}

export function buildBeautyConfig(ctx) {
  const state = ctx._beautyState || {}
  const enabled = !!state.beautyEnabled

  const softlightStrength = enabled ? Number(state.softlightStrength ?? 0) : 0
  const faceNarrowing = enabled ? Number(state.faceNarrowing ?? 0) : 0
  const eyeRounding = enabled ? Number(state.eyeRounding ?? 0) : 0
  const eyeEnlargement = enabled ? Number(state.eyeEnlargement ?? 0) : 0
  const lipsSize = enabled ? Number(state.lipsSize ?? 0) : 0
  const lipsMouthSize = enabled ? Number(state.lipsMouthSize ?? 0) : 0
  const noseLength = enabled ? Number(state.noseLength ?? 0) : 0

  return {
    faces: [
      {
        morphing: {
          eyes: {
            rounding: eyeRounding,
            enlargement: eyeEnlargement,
            height: 0,
            spacing: 0,
            squint: 0,
            lower_eyelid_pos: 0,
            lower_eyelid_size: 0,
            down: 0,
            eyelid_upper: 0,
            eyelid_lower: 0,
          },
          face: {
            narrowing: faceNarrowing,
            v_shape: 0,
            cheekbones_narrowing: 0,
            cheeks_narrowing: 0,
            jaw_narrowing: 0,
            chin_shortening: 0,
            chin_narrowing: 0,
            sunken_cheeks: 0,
            cheeks_and_jaw_narrowing: 0,
            jaw_wide_thin: 0,
            chin: 0,
            forehead: 0,
          },
          nose: {
            width: 0,
            length: noseLength,
            tip_width: 0,
            down_up: 0,
            sellion: 0,
          },
          lips: {
            size: lipsSize,
            height: 0,
            thickness: 0,
            mouth_size: lipsMouthSize,
            smile: 0,
            shape: 0,
            sharp: 0,
          },
        },
        eyes_whitening: {
          strength: 1,
        },
        eyes_flare: {
          strength: 1,
        },
        teeth_whitening: {
          strength: 1,
        },
        softlight: {
          strength: softlightStrength,
        },
      },
    ],
    scene: "effect C8bSOT83XWnng4YKk1Q4j",
    version: "2.0.0",
    camera: {},
    files: [],
  }
}

export async function applyBeautyConfig(ctx) {
  if (!ctx._banubaPlayer) return
  if (ctx._selectedEffect !== "beauty") return

  const config = buildBeautyConfig(ctx)
  const reloadConfig = ctx._banubaPlayer?._effectManager?.reloadConfig

  if (typeof reloadConfig !== "function") {
    throw new Error("banuba_reload_config_not_available")
  }

  await reloadConfig.call(
    ctx._banubaPlayer._effectManager,
    JSON.stringify(config)
  )
}

export async function applySelectedEffect(ctx) {
  if (!ctx._banubaPlayer) return

  const selectedEffect = ctx._selectedEffect || "beauty"
  console.log("[banuba] applySelectedEffect:", selectedEffect)

  if (selectedEffect === "none") {
    if (typeof ctx._banubaPlayer.clearEffect !== "function") {
      throw new Error("banuba_clear_effect_not_available")
    }

    await ctx._banubaPlayer.clearEffect()
    return
  }

  if (selectedEffect === "beauty") {
    const beautyEffect = ensureBeautyEffect(ctx)
    await ctx._banubaPlayer.applyEffect(beautyEffect)
    await applyBeautyConfig(ctx)
    return
  }

  throw new Error(`unsupported_selected_effect(${selectedEffect})`)
}

export async function ensureBanubaStarted(ctx) {
  if (ctx._banubaStarted && ctx._banubaPlayer) return

  if (!ctx.banubaClientTokenValue) {
    throw new Error("banuba_client_token_missing")
  }

  await ctx._ensureCameraVideoTrack()

  const sdkBase = normalizedBanubaSdkBaseUrl(ctx)

  const player = await Player.create({
    clientToken: ctx.banubaClientTokenValue,
    locateFile: {
      "BanubaSDK.data": `${sdkBase}/BanubaSDK.data`,
      "BanubaSDK.wasm": `${sdkBase}/BanubaSDK.wasm`,
      "BanubaSDK.simd.wasm": `${sdkBase}/BanubaSDK.simd.wasm`,
    },
  })

  const modules = []

  if (ctx.banubaFaceTrackerUrlValue) {
    modules.push(new Module(ctx.banubaFaceTrackerUrlValue))
  }

  if (ctx.banubaEyesUrlValue) {
    modules.push(new Module(ctx.banubaEyesUrlValue))
  }

  if (ctx.banubaLipsUrlValue) {
    modules.push(new Module(ctx.banubaLipsUrlValue))
  }

  if (ctx.banubaSkinUrlValue) {
    modules.push(new Module(ctx.banubaSkinUrlValue))
  }

  if (modules.length > 0) {
    await player.addModule(...modules)
  }

  const rawCameraStream = new window.MediaStream()
  if (ctx._cameraVideoTrack) {
    rawCameraStream.addTrack(ctx._cameraVideoTrack)
  }

  const banubaInput = new BanubaMediaStream(rawCameraStream)
  await player.use(banubaInput, { horizontalFlip: false })

  if (!ctx.hasBanubaSurfaceTarget) {
    throw new Error("banuba_surface_missing")
  }

  Dom.render(player, ctx.banubaSurfaceTarget)

  ctx._banubaPlayer = player
  ctx._banubaStarted = true

  ensureBeautyEffect(ctx)
  await applySelectedEffect(ctx)

  ctx._banubaRenderedNode = await waitForBanubaRenderedNode(ctx)
  await syncBanubaRenderedNode(ctx, ctx._banubaRenderedNode)
  ctx._syncCanvasResolutionToMeasured()
}

export async function ensureBanubaPublishTrack(ctx) {
  await ensureBanubaStarted(ctx)

  if (ctx._banubaVideoTrack && ctx._banubaStageStream) return

  const renderedNode = ctx._banubaRenderedNode || await waitForBanubaRenderedNode(ctx)
  ctx._banubaRenderedNode = renderedNode

  await syncBanubaRenderedNode(ctx, renderedNode)
  ctx._syncCanvasResolutionToMeasured()

  let stream = null

  if (renderedNode?.tagName === "CANVAS" && typeof renderedNode.captureStream === "function") {
    stream = renderedNode.captureStream(30)
  } else if (typeof renderedNode?.captureStream === "function") {
    stream = renderedNode.captureStream(30)
  }

  const track = stream?.getVideoTracks?.()[0] || null

  if (!track) {
    throw new Error("banuba_publish_track_unavailable")
  }

  ctx._banubaStream = stream
  ctx._banubaVideoTrack = track

  const { LocalStageStream } = window.IVSBroadcastClient || {}
  ctx._banubaStageStream = (track && LocalStageStream) ? new LocalStageStream(track) : null
}
