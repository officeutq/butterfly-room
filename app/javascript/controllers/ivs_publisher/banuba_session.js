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

  if (ctx.hasBanubaSurfaceTarget) {
    ctx.banubaSurfaceTarget.innerHTML = ""
  }
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

  if (ctx.banubaEffectUrlValue) {
    player.applyEffect(new Effect(ctx.banubaEffectUrlValue))
  }

  ctx._banubaPlayer = player
  ctx._banubaStarted = true
  ctx._banubaRenderedNode = await waitForBanubaRenderedNode(ctx)
  ctx._syncCanvasResolutionToMeasured()
}

export async function ensureBanubaPublishTrack(ctx) {
  await ensureBanubaStarted(ctx)

  if (ctx._banubaVideoTrack && ctx._banubaStageStream) return

  const renderedNode = ctx._banubaRenderedNode || await waitForBanubaRenderedNode(ctx)
  ctx._banubaRenderedNode = renderedNode
  ctx._syncCanvasResolutionToMeasured()

  let stream = null

  if (renderedNode?.tagName === "CANVAS" && typeof renderedNode.captureStream === "function") {
    stream = renderedNode.captureStream(15)
  } else if (typeof renderedNode?.captureStream === "function") {
    stream = renderedNode.captureStream(15)
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
