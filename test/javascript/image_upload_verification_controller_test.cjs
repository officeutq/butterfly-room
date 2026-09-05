const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const cropperEditorPath = path.resolve(
  __dirname,
  "../../app/javascript/image_attachments/cropper_editor.js"
)
const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/image_upload_verification_controller.js"
)

function loadController() {
  const cropperEditorSource = fs.readFileSync(cropperEditorPath, "utf8")
    .replaceAll("export ", "")
  let controllerSource = fs.readFileSync(controllerPath, "utf8")
  const revokedUrls = []

  controllerSource = controllerSource.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  controllerSource = controllerSource.replace('import Cropper from "cropperjs"', "class Cropper {}")
  controllerSource = controllerSource.replace(
    /import \{[\s\S]+?\} from "image_attachments\/cropper_editor"/,
    `const constrainCommonTransform = constrainTransformToSelection
     const commonCropStateFromTransform = cropStateFromTransform
     const commonSelectionBoxForRatio = selectionBoxForRatio
     const commonTransformFromCropState = transformFromCropState`
  )
  controllerSource = controllerSource.replace(
    'import { ImageSourceNormalizer } from "image_attachments/source_normalizer"',
    "class ImageSourceNormalizer { cancel() {} }"
  )
  controllerSource = controllerSource.replace(
    'import { prepareHeicInput } from "controllers/image_upload_verification/heic_converter"',
    ""
  )
  controllerSource = controllerSource.replace(
    'import { UploadVerificationClient } from "controllers/image_upload_verification/upload_client"',
    ""
  )
  controllerSource = controllerSource.replace(
    "export default class extends Controller",
    "globalThis.ImageUploadVerificationController = class extends Controller"
  )

  const context = vm.createContext({
    URL: {
      createObjectURL: () => "blob:generated",
      revokeObjectURL: (url) => revokedUrls.push(url),
    },
    console,
    requestAnimationFrame: (callback) => callback(),
  })
  vm.runInContext(`${cropperEditorSource}\n${controllerSource}`, context, { filename: controllerPath })

  return { Controller: context.ImageUploadVerificationController, revokedUrls }
}

function fakeClassList() {
  return {
    add() {},
    remove() {},
    toggle() {},
  }
}

test("source load resolves on load and rejects when replaced instead of leaving a pending task", async () => {
  const { Controller } = loadController()
  const controller = new Controller()
  const listeners = new Map()
  controller.sourceTarget = {
    complete: false,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
  }
  const loaded = controller.waitForSourceImage()
  listeners.get("load")()
  await loaded
  assert.equal(listeners.size, 0)
  const cancelled = controller.waitForSourceImage()
  controller.clearPendingSourceLoad()
  await assert.rejects(cancelled, /中止/)
  assert.equal(listeners.size, 0)
})

test("transform guard applies the shared correction without recursive updates", () => {
  const { Controller } = loadController()
  const controller = new Controller()
  controller.sourceTarget = { naturalWidth: 1200, naturalHeight: 630 }
  controller.ratioTarget = { value: "social" }
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

test("disconnect destroys Cropper and revokes source and preview object URLs", () => {
  const environment = loadController()
  const controller = new environment.Controller()
  let destroyCount = 0
  let imageListenerRemoved = false
  let canvasListenerRemoved = false

  Object.assign(controller, {
    controlTargets: [],
    heicModeTarget: { value: "worker" },
    heicLimitTarget: { value: "large" },
    heicLimitWarningTarget: {},
    cancelConversionTarget: {},
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
    normalizedPreviewTarget: { removeAttribute() {} },
    normalizationReportTarget: {},
    normalizationWarningTarget: {},
    sourceMetadataTarget: {},
    sourceDownloadTarget: { classList: fakeClassList(), removeAttribute() {}, setAttribute() {} },
    statusTarget: { classList: fakeClassList(), textContent: "" },
  })
  controller.connect()
  assert.equal(controller.heicLimitTarget.value, "standard", "reconnection must require a fresh opt-in")
  assert.equal(controller.heicLimitWarningTarget.hidden, true)
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
