const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

function loadEditor() {
  const source = fs.readFileSync(path.resolve(__dirname, "../../app/javascript/image_attachments/cropper_editor.js"), "utf8")
    .replaceAll("export ", "")
  const context = vm.createContext({})
  vm.runInContext(`${source}\nglobalThis.api = {
    IMAGE_CROP_CONFIGS,
    IMAGE_CROP_JPEG_QUALITY,
    constrainTransformToSelection,
    cropStateFromTransform,
    cropperTemplateFor,
    normalizeCropToSource,
    selectionBoxForRatio,
    transformCoversSelection,
    transformFromCropState,
    validateCropState,
  }`, context)
  return context.api
}

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

function socialState(overrides = {}) {
  return {
    schemaVersion: 1,
    ratioKey: "social",
    sourceBlobId: 42,
    source: { width: 1421, height: 800 },
    crop: { x: 184.7813, y: 0, width: 1032.6875, height: 542.1609 },
    zoom: 1.376,
    output: { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 },
    ...overrides,
  }
}

test("fixed crop configurations match the Rails pair contract", () => {
  const { IMAGE_CROP_CONFIGS, IMAGE_CROP_JPEG_QUALITY, cropperTemplateFor } = loadEditor()
  assert.deepEqual(plain(IMAGE_CROP_CONFIGS), {
    square: { ratio: 1, width: 1024, height: 1024 },
    social: { ratio: 40 / 21, width: 1200, height: 630 },
  })
  assert.equal(IMAGE_CROP_JPEG_QUALITY, 0.9)
  for (const ratioKey of ["square", "social"]) {
    const template = cropperTemplateFor(ratioKey)
    assert.match(template, /scalable translatable/)
    assert.doesNotMatch(template, /rotatable|skewable|resizable|min-fit/)
  }
  assert.throws(() => cropperTemplateFor("wide"), /対応していない/)
})

test("source pixel crop state round-trips without Cropper.js-specific data", () => {
  const { cropStateFromTransform, transformFromCropState } = loadEditor()
  const sourceWidth = 1200
  const sourceHeight = 630
  const selection = { x: 100, y: 100, width: 300, height: 157.5 }
  const matrix = [0.5, 0, 0, 0.5, -300, -107.5]
  const state = cropStateFromTransform({ selection, matrix, sourceWidth, sourceHeight, ratioKey: "social" })

  assert.deepEqual(plain(state), {
    schemaVersion: 1,
    ratioKey: "social",
    source: { width: 1200, height: 630 },
    crop: { x: 200, y: 100, width: 600, height: 315 },
    zoom: 2,
    output: { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 },
  })
  assert.deepEqual(Array.from(transformFromCropState({ crop: state.crop, selection, sourceWidth, sourceHeight })), matrix)
})

test("same source crop restores after the editor selection size changes", () => {
  const { cropStateFromTransform, transformFromCropState } = loadEditor()
  const crop = { x: 120, y: 80, width: 800, height: 420 }
  const selection = { x: 40, y: 60, width: 400, height: 210 }
  const source = { sourceWidth: 1200, sourceHeight: 630 }
  const matrix = transformFromCropState({ crop, selection, ...source })
  const restored = cropStateFromTransform({ selection, matrix, ...source, ratioKey: "social" })

  assert.deepEqual(plain(restored.crop), crop)
})

test("stored state requires matching purpose, source dimensions, source ID, output and zoom", () => {
  const { validateCropState } = loadEditor()
  const input = socialState()
  const validated = validateCropState({
    state: input,
    ratioKey: "social",
    sourceWidth: 1421,
    sourceHeight: 800,
    sourceBlobId: 42,
  })
  assert.deepEqual(plain(validated), input)

  const invalid = [
    [socialState({ ratioKey: "square" }), "unsupported_state"],
    [socialState({ sourceBlobId: 41 }), "source_id_mismatch"],
    [socialState({ source: { width: 800, height: 1421 } }), "source_mismatch"],
    [socialState({ output: { width: 1024, height: 1024, mimeType: "image/jpeg", quality: 0.9 } }), "unsupported_state"],
    [socialState({ zoom: 1 }), "invalid_zoom"],
    [socialState({ crop: { x: 0, y: 0, width: 100, height: 100 } }), "invalid_crop_ratio"],
  ]
  for (const [state, code] of invalid) {
    assert.throws(
      () => validateCropState({ state, ratioKey: "social", sourceWidth: 1421, sourceHeight: 800, sourceBlobId: 42 }),
      (error) => error.code === code
    )
  }
})

test("subpixel overflow is normalized without changing crop size", () => {
  const { normalizeCropToSource } = loadEditor()
  const crop = { x: 184.7813, y: -0.768, width: 1032.6875, height: 542.1609 }
  const normalized = normalizeCropToSource({ crop, sourceWidth: 1421, sourceHeight: 800, tolerance: 1 })

  assert.deepEqual(plain(normalized), { ...crop, y: 0 })
  assert.throws(() => normalizeCropToSource({
    crop: { ...crop, y: -2 }, sourceWidth: 1421, sourceHeight: 800, tolerance: 1,
  }), /編集元画像の外側/)
})

test("zoom-out reaches the fixed selection minimum for both ratios and image orientations", () => {
  const {
    constrainTransformToSelection,
    cropStateFromTransform,
    selectionBoxForRatio,
    transformCoversSelection,
  } = loadEditor()

  for (const [sourceWidth, sourceHeight] of [[1421, 800], [800, 1421]]) {
    for (const [ratioKey, ratio] of [["square", 1], ["social", 40 / 21]]) {
      const selection = selectionBoxForRatio({ canvasWidth: 800, canvasHeight: 500, ratio })
      const source = { sourceWidth, sourceHeight, selection }
      const matrix = constrainTransformToSelection({ ...source, matrix: [0.01, 0, 0, 0.01, 100, 200] })
      const minimumScale = Math.max(selection.width / sourceWidth, selection.height / sourceHeight)

      assert.equal(matrix[0], minimumScale)
      assert.equal(matrix[3], minimumScale)
      assert.equal(transformCoversSelection({ ...source, matrix, tolerance: 1e-7 }), true)
      const state = cropStateFromTransform({ ...source, matrix, ratioKey })
      assert.ok(state.crop.width === sourceWidth || state.crop.height === sourceHeight)
      assert.ok(Math.abs(state.crop.width / state.crop.height - ratio) < 1e-6)
      assert.ok(state.crop.x >= 0 && state.crop.y >= 0)
    }
  }
})

test("zoom-out at an edge is corrected and repeated minimum zoom stays stable", () => {
  const { constrainTransformToSelection, cropStateFromTransform, transformFromCropState } = loadEditor()
  const source = {
    sourceWidth: 1421,
    sourceHeight: 800,
    selection: { x: 100, y: 100, width: 600, height: 315 },
  }
  const edge = transformFromCropState({ ...source, crop: { x: 0, y: 0, width: 600, height: 315 } })
  const edgeScale = edge[0] / 1.1
  const corrected = constrainTransformToSelection({
    ...source, oldMatrix: edge, matrix: [edgeScale, 0, 0, edgeScale, edge[4], edge[5]],
  })
  const edgeState = cropStateFromTransform({ ...source, matrix: corrected, ratioKey: "social" })
  assert.equal(edgeState.crop.x, 0)
  assert.equal(edgeState.crop.y, 0)

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
})

test("unsupported transforms are rejected before they can distort the image", () => {
  const { constrainTransformToSelection } = loadEditor()
  const source = {
    sourceWidth: 1200,
    sourceHeight: 630,
    selection: { x: 100, y: 100, width: 600, height: 315 },
  }
  for (const matrix of [[0, 0, 0, 0, 0, 0], [1, 0, 0, 2, 0, 0], [1, 0.2, 0, 1, 0, 0], [NaN, 0, 0, 1, 0, 0]]) {
    assert.equal(constrainTransformToSelection({ ...source, matrix }), null)
  }
})
