const assert = require("node:assert/strict")
const test = require("node:test")
const browsers = require("@playwright/test")
const { openImageAttachmentEditorPage } = require("./helpers/image_attachment_editor_page.cjs")

test("shared editor creates fixed-size replacement files without blank borders", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openImageAttachmentEditorPage(browser)
    const results = await environment.page.evaluate(async () => {
      const outputs = []
      for (const [ratioKey, width, height] of [["square", 1024, 1024], ["social", 1200, 630]]) {
        const controller = window.mountEditor({ ratioKey })
        const file = await window.imageFile({ width: 1421, height: 800 })
        await controller.selectFile({ currentTarget: { files: [file] } })
        controller.zoomIn()
        const beforeKeyboard = controller.cropperImage.$getTransform()
        let keyboardPrevented = false
        controller.moveWithKeyboard({
          key: "ArrowRight",
          preventDefault() { keyboardPrevented = true },
        })
        const afterKeyboard = controller.cropperImage.$getTransform()
        const keyboardMoved = afterKeyboard.some((value, index) => Math.abs(value - beforeKeyboard[index]) > 1e-7)
        controller.resetImage()
        for (let index = 0; index < 30; index += 1) controller.zoomOut()
        controller.cropperImage.$move(10000, -10000)
        const minimumState = controller.buildState()
        await controller.applyCrop()
        const state = JSON.parse(controller.cropDataInputTarget.value)
        const display = controller.displayInputTarget.files[0]
        const bitmap = await createImageBitmap(display)
        const canvas = document.createElement("canvas")
        canvas.width = bitmap.width
        canvas.height = bitmap.height
        const context = canvas.getContext("2d")
        context.drawImage(bitmap, 0, 0)
        const corners = [[0, 0], [bitmap.width - 1, 0], [0, bitmap.height - 1], [bitmap.width - 1, bitmap.height - 1]]
          .map(([x, y]) => Array.from(context.getImageData(x, y, 1, 1).data))
        const decoded = { width: bitmap.width, height: bitmap.height }
        bitmap.close()
        canvas.width = 0
        canvas.height = 0
        outputs.push({
          ratioKey,
          expected: { width, height },
          operation: controller.operationInputTarget.value,
          source: {
            count: controller.sourceInputTarget.files.length,
            name: controller.sourceInputTarget.files[0]?.name,
            type: controller.sourceInputTarget.files[0]?.type,
          },
          display: { count: controller.displayInputTarget.files.length, name: display.name, type: display.type, width, height },
          decoded,
          state,
          minimumState,
          corners,
          keyboardMoved,
          keyboardPrevented,
        })
      }
      return outputs
    })

    for (const result of results) {
      assert.equal(result.operation, "replace")
      assert.deepEqual(result.source, { count: 1, name: "source.jpg", type: "image/jpeg" })
      assert.deepEqual(result.display, { count: 1, name: "display.jpg", type: "image/jpeg", ...result.expected })
      assert.deepEqual(result.decoded, result.expected)
      assert.equal(result.state.schemaVersion, 1)
      assert.equal(result.state.ratioKey, result.ratioKey)
      assert.equal(result.state.output.quality, 0.9)
      assert.equal("matrix" in result.state, false)
      assert.equal(result.keyboardMoved, true)
      assert.equal(result.keyboardPrevented, true)
      assert.ok(result.minimumState.crop.width === result.minimumState.source.width ||
        result.minimumState.crop.height === result.minimumState.source.height)
      for (const corner of result.corners) {
        assert.ok(Math.abs(corner[0] - 20) < 20 && Math.abs(corner[1] - 80) < 20 && Math.abs(corner[2] - 160) < 20)
      }
    }
    assert.deepEqual(environment.errors, [])
  } finally {
    await environment?.close()
    await browser.close()
  }
})

test("shared editor restores, stages re-edit/delete, cancels, and reconnects safely", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openImageAttachmentEditorPage(browser)
    const result = await environment.page.evaluate(async () => {
      const current = await window.currentImage()
      const controller = window.mountEditor(current)
      const baseline = {
        phase: controller.phase,
        preview: !controller.currentPreviewTarget.hidden,
        edit: !controller.editButtonTarget.hidden,
        deletion: !controller.deletionNoticeTarget.hidden,
      }
      await controller.editExisting()
      const restored = controller.buildState()
      const submitWhileEditing = new Event("submit", { bubbles: true, cancelable: true })
      const submitAllowed = document.querySelector("#form").dispatchEvent(submitWhileEditing)
      await controller.applyCrop()
      const reedit = {
        operation: controller.operationInputTarget.value,
        sourceCount: controller.sourceInputTarget.files.length,
        displayCount: controller.displayInputTarget.files.length,
        output: JSON.parse(controller.cropDataInputTarget.value).output,
      }
      controller.undoChange()
      controller.removeImage()
      const deletion = {
        operation: controller.operationInputTarget.value,
        sourceCount: controller.sourceInputTarget.files.length,
        displayCount: controller.displayInputTarget.files.length,
        cropData: controller.cropDataInputTarget.value,
        visible: !controller.deletionNoticeTarget.hidden,
      }
      controller.undoChange()
      const replacement = await window.imageFile({ width: 1421, height: 800 })
      await controller.selectFile({ currentTarget: { files: [replacement] } })
      controller.cancelEdit()
      const cancelled = {
        phase: controller.phase,
        operation: controller.operationInputTarget.value,
        sourceCount: controller.sourceInputTarget.files.length,
        displayCount: controller.displayInputTarget.files.length,
        preview: !controller.currentPreviewTarget.hidden,
      }
      await controller.selectFile({ currentTarget: { files: [replacement] } })
      const firstCropper = controller.cropper
      controller.disconnect()
      const destroyed = controller.cropper === null && controller.cropperImage === null
      controller.connect()
      await controller.selectFile({ currentTarget: { files: [replacement] } })
      const reconnect = {
        destroyed,
        replaced: controller.cropper !== firstCropper,
        canvasCount: controller.editorTarget.querySelectorAll("cropper-canvas").length,
      }

      const wrong = await window.currentImage({ stateSourceBlobId: 41 })
      const wrongController = window.mountEditor(wrong)
      await wrongController.editExisting()
      const mismatch = {
        phase: wrongController.phase,
        operation: wrongController.operationInputTarget.value,
        cropper: !!wrongController.cropper,
        status: wrongController.statusTarget.textContent,
      }
      return { baseline, restored, submitAllowed, reedit, deletion, cancelled, reconnect, mismatch }
    })

    assert.deepEqual(result.baseline, { phase: "idle", preview: true, edit: true, deletion: false })
    assert.ok(Math.abs(result.restored.crop.x - 100) < 0.001)
    assert.ok(Math.abs(result.restored.crop.y - 100) < 0.001)
    assert.equal(result.submitAllowed, false)
    assert.deepEqual(result.reedit, {
      operation: "reedit",
      sourceCount: 0,
      displayCount: 1,
      output: { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 },
    })
    assert.deepEqual(result.deletion, {
      operation: "delete", sourceCount: 0, displayCount: 0, cropData: "", visible: true,
    })
    assert.deepEqual(result.cancelled, {
      phase: "idle", operation: "", sourceCount: 0, displayCount: 0, preview: true,
    })
    assert.deepEqual(result.reconnect, { destroyed: true, replaced: true, canvasCount: 1 })
    assert.equal(result.mismatch.phase, "idle")
    assert.equal(result.mismatch.operation, "")
    assert.equal(result.mismatch.cropper, false)
    assert.match(result.mismatch.status, /編集元画像がクロップ情報と一致しません/)
    assert.deepEqual(environment.errors, [])
  } finally {
    await environment?.close()
    await browser.close()
  }
})
