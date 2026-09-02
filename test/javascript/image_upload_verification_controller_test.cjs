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
    globalThis.normalizeCropToSource = normalizeCropToSource
    globalThis.transformFromCropState = transformFromCropState
    globalThis.selectionBoxForRatio = selectionBoxForRatio
    globalThis.transformCoversSelection = transformCoversSelection
    globalThis.constrainTransformToSelection = constrainTransformToSelection
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
    normalizeCropToSource: context.normalizeCropToSource,
    transformFromCropState: context.transformFromCropState,
    selectionBoxForRatio: context.selectionBoxForRatio,
    transformCoversSelection: context.transformCoversSelection,
    constrainTransformToSelection: context.constrainTransformToSelection,
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

test("normalizes Cropper.js subpixel overflow without changing crop size", () => {
  const { normalizeCropToSource } = loadController()
  const crop = {
    x: 184.7813,
    y: -0.768,
    width: 1032.6875,
    height: 542.1609,
  }
  const normalized = normalizeCropToSource({
    crop,
    sourceWidth: 1421,
    sourceHeight: 800,
    tolerance: 1,
  })

  assert.deepEqual(JSON.parse(JSON.stringify(normalized)), {
    x: 184.7813,
    y: 0,
    width: 1032.6875,
    height: 542.1609,
  })
  assert.throws(() => normalizeCropToSource({
    crop: { ...crop, y: -2 },
    sourceWidth: 1421,
    sourceHeight: 800,
    tolerance: 1,
  }), /編集元画像の外側/)
})

test("serialized crop state stays inside the source at a subpixel boundary", () => {
  const { cropStateFromTransform } = loadController()
  const state = cropStateFromTransform({
    selection: { x: 184.7813, y: 100, width: 1032.6875, height: 542.1609 },
    matrix: [1, 0, 0, 1, 0, 100.768],
    sourceWidth: 1421,
    sourceHeight: 800,
    ratioKey: "social",
  })

  assert.equal(state.crop.y, 0)
  assert.equal(state.crop.height, 542.1609)
  assert.ok(state.crop.y + state.crop.height <= state.source.height)
})

test("restore accepts and normalizes the reported social crop state", () => {
  const { Controller } = loadController()
  const controller = new Controller()
  controller.sourceTarget = { naturalWidth: 1421, naturalHeight: 800 }
  const state = controller.validateState({
    schemaVersion: 1,
    ratioKey: "social",
    source: { width: 1421, height: 800 },
    crop: {
      x: 184.7813,
      y: -0.768,
      width: 1032.6875,
      height: 542.1609,
    },
  })

  assert.equal(state.crop.y, 0)
  assert.equal(state.crop.width, 1032.6875)
  assert.equal(state.crop.height, 542.1609)
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

test("zoom-out reaches the selection minimum for both ratios and image orientations", () => {
  const { constrainTransformToSelection, cropStateFromTransform, selectionBoxForRatio, transformCoversSelection } = loadController()

  for (const [sourceWidth, sourceHeight] of [[1421, 800], [800, 1421]]) {
    for (const [ratioKey, ratio] of [["square", 1], ["social", 40 / 21]]) {
      const selection = selectionBoxForRatio({ canvasWidth: 800, canvasHeight: 500, ratio })
      const source = { sourceWidth, sourceHeight, selection }
      const matrix = constrainTransformToSelection({ ...source, matrix: [0.01, 0, 0, 0.01, 100, 200] })
      const minimumScale = Math.max(selection.width / sourceWidth, selection.height / sourceHeight)

      assert.equal(matrix[0], minimumScale)
      assert.equal(matrix[3], minimumScale)
      assert.ok(minimumScale < Math.max(800 / sourceWidth, 500 / sourceHeight))
      assert.equal(transformCoversSelection({ ...source, matrix, tolerance: 1e-7 }), true)

      const state = cropStateFromTransform({ ...source, matrix, ratioKey })
      assert.ok(state.crop.width === sourceWidth || state.crop.height === sourceHeight)
      assert.ok(Math.abs(state.crop.width / state.crop.height - ratio) < 1e-6)
      assert.ok(state.crop.x >= 0 && state.crop.y >= 0)
    }
  }
})

test("zoom-out at an image edge corrects the position instead of rejecting the zoom", () => {
  const { constrainTransformToSelection, cropStateFromTransform, transformFromCropState } = loadController()
  const source = {
    sourceWidth: 1421,
    sourceHeight: 800,
    selection: { x: 100, y: 100, width: 600, height: 315 },
  }
  const oldMatrix = transformFromCropState({ ...source, crop: { x: 0, y: 0, width: 600, height: 315 } })
  const scale = oldMatrix[0] / 1.1
  const matrix = constrainTransformToSelection({
    ...source,
    oldMatrix,
    matrix: [scale, 0, 0, scale, oldMatrix[4], oldMatrix[5]],
  })
  const state = cropStateFromTransform({ ...source, matrix, ratioKey: "social" })

  assert.equal(matrix[0], scale)
  assert.equal(state.crop.x, 0)
  assert.equal(state.crop.y, 0)
  assert.ok(state.crop.width > 600)
})

test("zoom-out stays stable at the minimum and allows zooming back in", () => {
  const { constrainTransformToSelection, transformFromCropState } = loadController()
  const source = {
    sourceWidth: 1421,
    sourceHeight: 800,
    selection: { x: 100, y: 100, width: 600, height: 315 },
  }
  const minimum = transformFromCropState({
    ...source, crop: { x: 0, y: 0, width: 1421, height: 1421 * 21 / 40 },
  })
  let matrix = minimum

  for (let index = 0; index < 20; index += 1) {
    const scale = matrix[0] / 1.1
    matrix = constrainTransformToSelection({
      ...source, oldMatrix: matrix, matrix: [scale, 0, 0, scale, matrix[4], matrix[5]],
    })
  }

  matrix.forEach((value, index) => assert.ok(Math.abs(value - minimum[index]) < 1e-7))
  const zoomedIn = constrainTransformToSelection({
    ...source, oldMatrix: matrix, matrix: [matrix[0] * 1.1, 0, 0, matrix[3] * 1.1, matrix[4], matrix[5]],
  })
  assert.ok(zoomedIn[0] > matrix[0])
})

test("transform guard applies a corrected matrix without recursive updates", () => {
  const { Controller } = loadController()
  const controller = new Controller()
  controller.sourceTarget = { naturalWidth: 1200, naturalHeight: 630 }
  controller.cropperSelection = { x: 100, y: 100, width: 600, height: 315 }
  let current = [1, 0, 0, 1, 0, 0]
  let calls = 0
  controller.cropperImage = {
    $setTransform(matrix) {
      calls += 1
      assert.ok(calls <= 2, "guard must not recurse after correction")
      let prevented = false
      controller.constrainTransform({
        detail: { matrix, oldMatrix: current },
        preventDefault() { prevented = true },
      })
      if (!prevented) current = matrix
    },
  }

  controller.cropperImage.$setTransform([0.1, 0, 0, 0.1, 0, 0])

  assert.equal(calls, 2)
  assert.equal(current[0], 0.5)
  assert.equal(current[3], 0.5)
  assert.doesNotMatch(controller.cropperTemplate(40 / 21), /min-fit=/)
})

test("unsupported transforms are rejected before they can distort the image", () => {
  const { constrainTransformToSelection } = loadController()
  const source = {
    sourceWidth: 1200,
    sourceHeight: 630,
    selection: { x: 100, y: 100, width: 600, height: 315 },
  }
  for (const matrix of [[0, 0, 0, 0, 0, 0], [1, 0, 0, 2, 0, 0], [1, 0.2, 0, 1, 0, 0], [NaN, 0, 0, 1, 0, 0]]) {
    assert.equal(constrainTransformToSelection({ ...source, matrix }), null)
  }
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
