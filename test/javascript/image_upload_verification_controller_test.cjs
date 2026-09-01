const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/image_upload_verification_controller.js"
)

function loadController() {
  let source = fs.readFileSync(controllerPath, "utf8")
  const revokedUrls = []

  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace('import Cropper from "cropperjs"', "class Cropper {}")
  source = source.replaceAll("export function ", "function ")
  source = source.replace(
    "export default class extends Controller",
    "globalThis.ImageUploadVerificationController = class extends Controller"
  )
  source += `
    globalThis.cropStateFromTransform = cropStateFromTransform
    globalThis.transformFromCropState = transformFromCropState
    globalThis.selectionBoxForRatio = selectionBoxForRatio
    globalThis.transformCoversSelection = transformCoversSelection
  `

  const context = vm.createContext({
    URL: {
      createObjectURL: () => "blob:generated",
      revokeObjectURL: (url) => revokedUrls.push(url),
    },
    console,
    requestAnimationFrame: (callback) => callback(),
  })
  vm.runInContext(source, context, { filename: controllerPath })

  return {
    Controller: context.ImageUploadVerificationController,
    cropStateFromTransform: context.cropStateFromTransform,
    transformFromCropState: context.transformFromCropState,
    selectionBoxForRatio: context.selectionBoxForRatio,
    transformCoversSelection: context.transformCoversSelection,
    revokedUrls,
  }
}

function fakeClassList() {
  return {
    add() {},
    remove() {},
    toggle() {},
  }
}

test("fixed selection box stays centered at 40:21", () => {
  const { selectionBoxForRatio } = loadController()
  const box = selectionBoxForRatio({
    canvasWidth: 640,
    canvasHeight: 480,
    ratio: 40 / 21,
  })

  assert.equal(Math.round(box.width / box.height * 1000) / 1000, Math.round((40 / 21) * 1000) / 1000)
  assert.equal(box.x, (640 - box.width) / 2)
  assert.equal(box.y, (480 - box.height) / 2)
  assert.ok(box.width <= 640 * 0.82)
  assert.ok(box.height <= 480 * 0.82)
})

test("source pixel crop state round-trips without Cropper.js-specific data", () => {
  const { cropStateFromTransform, transformFromCropState } = loadController()
  const sourceWidth = 1200
  const sourceHeight = 630
  const selection = { x: 100, y: 100, width: 300, height: 157.5 }
  const matrix = [0.5, 0, 0, 0.5, -300, -107.5]

  const state = cropStateFromTransform({
    selection,
    matrix,
    sourceWidth,
    sourceHeight,
    ratioKey: "social",
  })

  assert.deepEqual(JSON.parse(JSON.stringify(state.crop)), {
    x: 200,
    y: 100,
    width: 600,
    height: 315,
  })
  assert.equal(state.zoom, 2)
  assert.deepEqual(JSON.parse(JSON.stringify(state.output)), {
    width: 1200,
    height: 630,
    mimeType: "image/jpeg",
    quality: 0.9,
  })

  const restoredMatrix = transformFromCropState({
    crop: state.crop,
    selection,
    sourceWidth,
    sourceHeight,
  })
  assert.deepEqual(Array.from(restoredMatrix), matrix)
})

test("same source crop restores after the editor selection size changes", () => {
  const { cropStateFromTransform, transformFromCropState } = loadController()
  const state = {
    crop: { x: 120, y: 80, width: 800, height: 420 },
  }
  const resizedSelection = { x: 40, y: 60, width: 400, height: 210 }
  const matrix = transformFromCropState({
    crop: state.crop,
    selection: resizedSelection,
    sourceWidth: 1200,
    sourceHeight: 630,
  })
  const restored = cropStateFromTransform({
    selection: resizedSelection,
    matrix,
    sourceWidth: 1200,
    sourceHeight: 630,
    ratioKey: "social",
  })

  assert.deepEqual(JSON.parse(JSON.stringify(restored.crop)), state.crop)
})

test("rejects transforms that would expose blank space inside the fixed selection", () => {
  const { transformCoversSelection } = loadController()
  const source = { sourceWidth: 1200, sourceHeight: 630 }
  const selection = { x: 100, y: 100, width: 400, height: 210 }

  assert.equal(transformCoversSelection({
    ...source,
    selection,
    matrix: [1, 0, 0, 1, 0, 0],
  }), true)
  assert.equal(transformCoversSelection({
    ...source,
    selection,
    matrix: [1, 0, 0, 1, 500, 0],
  }), false)
  assert.equal(transformCoversSelection({
    ...source,
    selection,
    matrix: [0.2, 0, 0, 0.2, 0, 0],
  }), false)
})

test("disconnect destroys Cropper and revokes source and preview object URLs", () => {
  const environment = loadController()
  const controller = new environment.Controller()
  let destroyCount = 0
  let imageListenerRemoved = false
  let canvasListenerRemoved = false

  Object.assign(controller, {
    controlTargets: [],
    downloadTarget: {
      classList: fakeClassList(),
      removeAttribute() {},
      setAttribute() {},
    },
    previewTarget: {
      classList: fakeClassList(),
      hidden: false,
      removeAttribute() {},
    },
    previewEmptyTarget: { hidden: true },
    previewMetadataTarget: { textContent: "" },
    statusTarget: { classList: fakeClassList(), textContent: "" },
  })
  controller.connect()
  controller.sourceObjectUrl = "blob:source"
  controller.previewObjectUrl = "blob:preview"
  controller.cropper = { destroy: () => { destroyCount += 1 } }
  controller.cropperImage = {
    removeEventListener: () => { imageListenerRemoved = true },
  }
  controller.cropperCanvas = {
    removeEventListener: () => { canvasListenerRemoved = true },
  }

  controller.disconnect()

  assert.equal(destroyCount, 1)
  assert.equal(imageListenerRemoved, true)
  assert.equal(canvasListenerRemoved, true)
  assert.deepEqual(environment.revokedUrls.sort(), ["blob:preview", "blob:source"])
})
