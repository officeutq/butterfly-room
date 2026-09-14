const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadHelpers() {
  const context = vm.createContext({ stopCanvasRenderLoop() {} })
  for (const filename of ["banuba_session.js", "media_state.js"]) {
    const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/controllers/ivs_publisher", filename), "utf8")
      .replace(/^import .*$/gm, "").replace(/export (async function|function) /g, "$1 ")
    vm.runInContext(source, context)
  }
  return context
}

test("R03 delayed old Banuba destruction cannot clear the replacement player or surface", async () => {
  const context = loadHelpers()
  let release
  const destroyed = new Promise(resolve => { release = resolve })
  let surfaceStops = 0
  const ctx = { _beautyProvider: {}, _banubaPlayer: { destroy: () => destroyed }, hasBanubaSurfaceTarget: true,
    banubaSurfaceTarget: { innerHTML: "old", querySelectorAll: () => { surfaceStops++; return [] } } }
  const cleaning = context.destroyBanubaPlayer(ctx)
  const replacement = { newPlayer: true }
  ctx._beautyProvider = {}
  ctx._banubaPlayer = replacement
  ctx.banubaSurfaceTarget.innerHTML = "new"
  release()
  await cleaning
  assert.equal(ctx._banubaPlayer, replacement)
  assert.equal(ctx.banubaSurfaceTarget.innerHTML, "new")
  assert.equal(surfaceStops, 1)
})

test("R03 delayed old provider cleanup cannot stop or clear replacement camera/audio tracks", async () => {
  const context = loadHelpers()
  let release
  const stopped = new Promise(resolve => { release = resolve })
  const ctx = { _beautyProvider: { stop: () => stopped } }
  const cleaning = context.cleanupMediaAndCanvas(ctx)
  let cameraStops = 0
  const newAudio = {}, newVideo = {}
  ctx._beautyProvider = {}
  ctx._cameraMedia = { getTracks: () => [{ stop() { cameraStops++ } }] }
  ctx._audioTrack = newAudio
  ctx._publishedVideoTrack = newVideo
  release()
  await cleaning
  assert.equal(ctx._audioTrack, newAudio)
  assert.equal(ctx._publishedVideoTrack, newVideo)
  assert.equal(cameraStops, 0)
})
