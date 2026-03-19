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

function selectedCustomEffectZipFilename(ctx) {
  if (typeof ctx._selectedEffectInput !== "function") return ""

  const input = ctx._selectedEffectInput()
  return input?.dataset?.effectZipFilename || ""
}

function ensureSelectedCustomEffect(ctx) {
  const selectedEffect = ctx._selectedEffect || ""
  if (!selectedEffect || selectedEffect === "none" || selectedEffect === "beauty") {
    throw new Error("selected_effect_is_not_custom")
  }

  const zipFilename = selectedCustomEffectZipFilename(ctx)
  if (!zipFilename) {
    throw new Error(`custom_effect_zip_filename_missing(${selectedEffect})`)
  }

  if (!ctx._banubaEffects) {
    ctx._banubaEffects = {}
  }

  if (!ctx._banubaEffects[selectedEffect]) {
    const url = `/banuba/effects/${encodeURIComponent(zipFilename)}`
    ctx._banubaEffects[selectedEffect] = new Effect(url)
  }

  return ctx._banubaEffects[selectedEffect]
}

function deepCloneJson(value) {
  return JSON.parse(JSON.stringify(value))
}

function isPlainObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value)
}

function ensureObject(value) {
  return isPlainObject(value) ? value : {}
}

function ensureArray(value) {
  return Array.isArray(value) ? value : []
}

function numberOrFallback(value, fallback = 0) {
  const num = Number(value)
  return Number.isFinite(num) ? num : fallback
}

function readNestedNumber(source, path, fallback = 0) {
  let current = source

  for (const key of path) {
    if (!isPlainObject(current) && !Array.isArray(current)) return fallback
    current = current?.[key]
  }

  return numberOrFallback(current, fallback)
}

function buildFallbackBeautyConfigSource() {
  return {
    faces: [
      {
        eyes_whitening: {
          strength: 0,
        },
        eyes_flare: {
          strength: 0,
        },
        teeth_whitening: {
          strength: 0,
        },
        softlight: {
          strength: 0,
        },
        morphing: {
          eyebrows: {
            spacing: 0,
            height: 0,
            bend: 0,
          },
          eyes: {
            rounding: 0,
            enlargement: 0,
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
            narrowing: 0,
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
            length: 0,
            tip_width: 0,
            down_up: 0,
            sellion: 0,
          },
          lips: {
            size: 0,
            height: 0,
            thickness: 0,
            mouth_size: 0,
            smile: 0,
            shape: 0,
            sharp: 0,
          },
        },
      },
    ],
    scene: "",
    version: "2.0.0",
    camera: {},
    files: [],
  }
}

async function loadBeautyConfigSource(ctx) {
  if (ctx._beautyConfigSourceLoaded) {
    return ctx._beautyConfigSource || buildFallbackBeautyConfigSource()
  }

  ctx._beautyConfigSourceLoaded = true

  const url = ctx.banubaBeautyConfigUrlValue || ""

  if (!url) {
    ctx._beautyConfigSource = buildFallbackBeautyConfigSource()
    return ctx._beautyConfigSource
  }

  try {
    const response = await fetch(url, {
      method: "GET",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
      },
    })

    if (!response.ok) {
      throw new Error(`beauty_config_fetch_failed(${response.status})`)
    }

    const json = await response.json()
    ctx._beautyConfigSource = deepCloneJson(json)
  } catch (e) {
    console.warn("[banuba] beauty config load failed, fallback to zeros", e)
    ctx._beautyConfigSource = buildFallbackBeautyConfigSource()
  }

  return ctx._beautyConfigSource
}

function buildInitialBeautyStateFromConfig(configSource) {
  const config = configSource || buildFallbackBeautyConfigSource()
  const face = ensureArray(config.faces)[0] || {}
  const morphing = ensureObject(face.morphing)

  return {
    beautyEnabled: true,
    softlightStrength: readNestedNumber(face, ["softlight", "strength"], 0),
    faceNarrowing: readNestedNumber(morphing, ["face", "narrowing"], 0),
    eyeRounding: readNestedNumber(morphing, ["eyes", "rounding"], 0),
    eyeEnlargement: readNestedNumber(morphing, ["eyes", "enlargement"], 0),
    lipsSize: readNestedNumber(morphing, ["lips", "size"], 0),
    lipsMouthSize: readNestedNumber(morphing, ["lips", "mouth_size"], 0),
    noseLength: readNestedNumber(morphing, ["nose", "length"], 0),
  }
}

export async function ensureInitialBeautyStateLoaded(ctx) {
  if (ctx._beautyStateInitialized) {
    return ctx._beautyState
  }

  if (ctx._beautyStateLoadPromise) {
    return ctx._beautyStateLoadPromise
  }

  ctx._beautyStateLoadPromise = (async () => {
    const configSource = await loadBeautyConfigSource(ctx)
    ctx._beautyState = buildInitialBeautyStateFromConfig(configSource)
    ctx._beautyStateInitialized = true

    if (typeof ctx._syncBeautySliderFromState === "function") {
      ctx._syncBeautySliderFromState()
    }

    return ctx._beautyState
  })()

  try {
    return await ctx._beautyStateLoadPromise
  } finally {
    ctx._beautyStateLoadPromise = null
  }
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

  const source = ctx._beautyConfigSource || buildFallbackBeautyConfigSource()
  const config = deepCloneJson(source)

  config.faces = ensureArray(config.faces)
  if (config.faces.length === 0) {
    config.faces.push({})
  }

  const face = ensureObject(config.faces[0])
  config.faces[0] = face

  face.softlight = ensureObject(face.softlight)
  face.morphing = ensureObject(face.morphing)
  face.morphing.eyes = ensureObject(face.morphing.eyes)
  face.morphing.face = ensureObject(face.morphing.face)
  face.morphing.nose = ensureObject(face.morphing.nose)
  face.morphing.lips = ensureObject(face.morphing.lips)

  config.camera = ensureObject(config.camera)
  config.files = ensureArray(config.files)
  config.version = config.version || "2.0.0"
  config.scene = typeof config.scene === "string" ? config.scene : ""

  face.softlight.strength = enabled ? numberOrFallback(state.softlightStrength, 0) : 0
  face.morphing.face.narrowing = enabled ? numberOrFallback(state.faceNarrowing, 0) : 0
  face.morphing.eyes.rounding = enabled ? numberOrFallback(state.eyeRounding, 0) : 0
  face.morphing.eyes.enlargement = enabled ? numberOrFallback(state.eyeEnlargement, 0) : 0
  face.morphing.nose.length = enabled ? numberOrFallback(state.noseLength, 0) : 0
  face.morphing.lips.size = enabled ? numberOrFallback(state.lipsSize, 0) : 0
  face.morphing.lips.mouth_size = enabled ? numberOrFallback(state.lipsMouthSize, 0) : 0

  return config
}

export async function applyBeautyConfig(ctx) {
  if (!ctx._banubaPlayer) return
  if (ctx._selectedEffect !== "beauty") return

  await ensureInitialBeautyStateLoaded(ctx)

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
    await ensureInitialBeautyStateLoaded(ctx)
    const beautyEffect = ensureBeautyEffect(ctx)
    await ctx._banubaPlayer.applyEffect(beautyEffect)
    await applyBeautyConfig(ctx)
    return
  }

  const customEffect = ensureSelectedCustomEffect(ctx)
  await ctx._banubaPlayer.applyEffect(customEffect)
}

export async function ensureBanubaStarted(ctx) {
  if (ctx._banubaStarted && ctx._banubaPlayer) return

  if (!ctx.banubaClientTokenValue) {
    throw new Error("banuba_client_token_missing")
  }

  await ensureInitialBeautyStateLoaded(ctx)
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
