export function syncCanvasResolutionToMeasured(ctx) {
  if (!ctx.hasCanvasTarget) return

  const width = Math.max(1, Math.round(ctx._measuredVideo?.width || 1280))
  const height = Math.max(1, Math.round(ctx._measuredVideo?.height || 720))

  if (ctx.canvasTarget.width !== width) ctx.canvasTarget.width = width
  if (ctx.canvasTarget.height !== height) ctx.canvasTarget.height = height
}

export function startCanvasRenderLoop(ctx) {
  if (!ctx.hasCanvasTarget) return
  if (ctx._raf) return

  const canvas = ctx.canvasTarget
  const ctx2d = canvas.getContext("2d")

  const draw = () => {
    try {
      const width = canvas.width
      const height = canvas.height

      ctx2d.clearRect(0, 0, width, height)

      ctx2d.fillStyle = "#111"
      ctx2d.fillRect(0, 0, width, height)

      const minSide = Math.min(width, height)
      const fontSize = Math.max(28, Math.round(minSide * 0.1))
      const subFontSize = Math.max(16, Math.round(minSide * 0.045))

      ctx2d.fillStyle = "#fff"
      ctx2d.textAlign = "center"
      ctx2d.textBaseline = "middle"
      ctx2d.font = `700 ${fontSize}px sans-serif`
      ctx2d.fillText("席外し中", width / 2, height / 2 - fontSize * 0.15)

      ctx2d.fillStyle = "rgba(255, 255, 255, 0.75)"
      ctx2d.font = `400 ${subFontSize}px sans-serif`
      ctx2d.fillText("しばらくお待ちください", width / 2, height / 2 + fontSize * 0.8)
    } catch (_) {
    }

    ctx._raf = requestAnimationFrame(draw)
  }

  ctx._raf = requestAnimationFrame(draw)
}

export function stopCanvasRenderLoop(ctx) {
  if (ctx._raf) cancelAnimationFrame(ctx._raf)
  ctx._raf = null

  if (!ctx.hasCanvasTarget) return

  const canvas = ctx.canvasTarget
  const ctx2d = canvas.getContext("2d")
  if (ctx2d) {
    try {
      ctx2d.clearRect(0, 0, canvas.width, canvas.height)
    } catch (_) {}
  }
}
