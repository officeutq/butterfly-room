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

test("shared editor lazily converts HEIC in a Worker before normalizing and cropping", { timeout: 120_000 }, async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openImageAttachmentEditorPage(browser, { strictCsp: true })
    assert.equal(environment.requests.includes("/worker.js"), false)
    assert.equal(environment.requests.includes("/decoder.js"), false)

    const result = await environment.page.evaluate(async () => {
      const invalidController = window.mountEditor({ ratioKey: "square" })
      await invalidController.selectFile({ currentTarget: { files: [new File(["broken"], "broken.heic", { type: "image/heic" })] } })
      const invalid = {
        phase: invalidController.phase,
        sourceCount: invalidController.sourceInputTarget.files.length,
        status: invalidController.statusTarget.textContent,
      }

      const controller = window.mountEditor({ ratioKey: "social" })
      const input = await (await fetch("/heic/medium.heic")).blob()
      await controller.selectFile({ currentTarget: { files: [new File([input], "medium.heic", { type: "image/heic" })] } })
      if (!controller.cropper) throw new Error(controller.statusTarget.textContent)
      const sourceBeforeCrop = {
        type: controller.workingSourceFile.type,
        name: controller.workingSourceFile.name,
      }
      await controller.applyCrop()
      const source = controller.sourceInputTarget.files[0]
      const display = controller.displayInputTarget.files[0]
      const state = JSON.parse(controller.cropDataInputTarget.value)
      return {
        invalid,
        sourceBeforeCrop,
        operation: controller.operationInputTarget.value,
        source: { type: source.type, name: source.name, bytes: source.size },
        display: { type: display.type, name: display.name, bytes: display.size },
        state,
      }
    })

    assert.equal(result.invalid.phase, "idle")
    assert.equal(result.invalid.sourceCount, 0)
    assert.match(result.invalid.status, /実体/)
    assert.deepEqual(result.sourceBeforeCrop, { type: "image/jpeg", name: "source.jpg" })
    assert.equal(result.operation, "replace")
    assert.equal(result.source.type, "image/jpeg")
    assert.equal(result.source.name, "source.jpg")
    assert.ok(result.source.bytes > 0)
    assert.equal(result.display.type, "image/jpeg")
    assert.equal(result.display.name, "display.jpg")
    assert.ok(result.display.bytes > 0)
    assert.equal(result.state.ratioKey, "social")
    assert.deepEqual(result.state.output, { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 })
    assert.ok(environment.requests.includes("/worker.js"))
    assert.ok(environment.requests.includes("/decoder.js"))
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

      const legacy = await window.currentImage()
      const legacyController = window.mountEditor({ currentDisplayUrl: legacy.currentDisplayUrl, ratioKey: "square" })
      const legacyBaseline = {
        preview: !legacyController.currentPreviewTarget.hidden,
        edit: !legacyController.editButtonTarget.hidden,
        deletion: !legacyController.deleteButtonTarget.hidden,
      }
      legacyController.removeImage()
      const legacyDeletion = {
        operation: legacyController.operationInputTarget.value,
        visible: !legacyController.deletionNoticeTarget.hidden,
      }
      return {
        baseline, restored, submitAllowed, reedit, deletion, cancelled, reconnect, mismatch,
        legacyBaseline, legacyDeletion,
      }
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
    assert.deepEqual(result.legacyBaseline, { preview: true, edit: false, deletion: true })
    assert.deepEqual(result.legacyDeletion, { operation: "delete", visible: true })
    assert.deepEqual(environment.errors, [])
  } finally {
    await environment?.close()
    await browser.close()
  }
})

test("profile editor keeps image actions and preserves staged crops when re-edit is cancelled", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openImageAttachmentEditorPage(browser)
    const result = await environment.page.evaluate(async () => {
      const current = await window.currentImage({ ratioKey: "square" })
      const controller = window.mountEditor({ ...current, keepStagedActions: true })

      await controller.editExisting()
      await controller.applyCrop()
      const stagedReeditPreview = controller.currentPreviewTarget.src
      const stagedReedit = {
        phase: controller.phase,
        operation: controller.operationInputTarget.value,
        editVisible: !controller.editButtonTarget.hidden,
        deleteVisible: !controller.deleteButtonTarget.hidden,
        undoVisible: !controller.undoButtonTarget.hidden,
      }
      await controller.editExisting({ currentTarget: controller.editButtonTarget })
      const reopenedReeditPhase = controller.phase
      controller.cancelEdit()
      const cancelledReedit = {
        phase: controller.phase,
        operation: controller.operationInputTarget.value,
        displayCount: controller.displayInputTarget.files.length,
        previewPreserved: controller.currentPreviewTarget.src === stagedReeditPreview,
      }

      controller.undoChange()
      const replacement = await window.imageFile({ width: 1200, height: 1200, name: "replacement.png" })
      await controller.selectFile({ currentTarget: { files: [replacement] } })
      await controller.applyCrop()
      const stagedReplacementPreview = controller.currentPreviewTarget.src
      const stagedReplacementSource = controller.sourceInputTarget.files[0]
      await controller.editExisting({ currentTarget: controller.editButtonTarget })
      const reopenedReplacementPhase = controller.phase
      controller.cancelEdit()
      const cancelledReplacement = {
        phase: controller.phase,
        operation: controller.operationInputTarget.value,
        sourceCount: controller.sourceInputTarget.files.length,
        sourcePreserved: controller.sourceInputTarget.files[0] === stagedReplacementSource,
        displayCount: controller.displayInputTarget.files.length,
        previewPreserved: controller.currentPreviewTarget.src === stagedReplacementPreview,
        editVisible: !controller.editButtonTarget.hidden,
        deleteVisible: !controller.deleteButtonTarget.hidden,
        undoVisible: !controller.undoButtonTarget.hidden,
      }

      return {
        stagedReedit,
        reopenedReeditPhase,
        cancelledReedit,
        reopenedReplacementPhase,
        cancelledReplacement,
      }
    })

    assert.deepEqual(result.stagedReedit, {
      phase: "staged-reedit", operation: "reedit", editVisible: true, deleteVisible: true, undoVisible: true,
    })
    assert.equal(result.reopenedReeditPhase, "editing-existing")
    assert.deepEqual(result.cancelledReedit, {
      phase: "staged-reedit", operation: "reedit", displayCount: 1, previewPreserved: true,
    })
    assert.equal(result.reopenedReplacementPhase, "editing-replacement")
    assert.deepEqual(result.cancelledReplacement, {
      phase: "staged-replace",
      operation: "replace",
      sourceCount: 1,
      sourcePreserved: true,
      displayCount: 1,
      previewPreserved: true,
      editVisible: true,
      deleteVisible: true,
      undoVisible: true,
    })
    assert.deepEqual(environment.errors, [])
  } finally {
    await environment?.close()
    await browser.close()
  }
})

test("two profile editors stay independent at smartphone width and source load failure is non-destructive", async () => {
  const browser = await browsers[process.env.IMAGE_VERIFICATION_BROWSER || "chromium"].launch({ headless: true })
  let environment
  try {
    environment = await openImageAttachmentEditorPage(browser)
    await environment.page.setViewportSize({ width: 390, height: 844 })
    const result = await environment.page.evaluate(async () => {
      const [avatar, cover] = window.mountEditors([
        { ratioKey: "square" },
        { ratioKey: "social" },
      ])
      const avatarFile = await window.imageFile({ width: 1200, height: 1200 })
      await avatar.selectFile({ currentTarget: { files: [avatarFile] } })
      await avatar.applyCrop()
      const afterAvatar = {
        avatar: avatar.operationInputTarget.value,
        cover: cover.operationInputTarget.value,
      }

      const coverFile = await window.imageFile({ width: 1200, height: 630 })
      await cover.selectFile({ currentTarget: { files: [coverFile] } })
      const coverEditorWidth = cover.editorTarget.clientWidth
      cover.cancelEdit()
      const afterCoverCancel = {
        avatar: avatar.operationInputTarget.value,
        cover: cover.operationInputTarget.value,
      }
      const form = document.querySelector("#form")
      let submitAllowed = false
      form.addEventListener("submit", (event) => {
        submitAllowed = !event.defaultPrevented
        event.preventDefault()
      }, { once: true })
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
      const mobile = {
        viewport: innerWidth,
        documentWidth: document.documentElement.scrollWidth,
        editorWidths: [coverEditorWidth],
      }

      const missing = await window.currentImage()
      missing.currentSourceUrl = "/missing-source.jpg"
      const failed = window.mountEditor(missing)
      await failed.editExisting()
      const loadFailure = {
        operation: failed.operationInputTarget.value,
        preview: !failed.currentPreviewTarget.hidden,
        workspace: !failed.workspaceTarget.hidden,
        status: failed.statusTarget.textContent,
      }
      return { afterAvatar, afterCoverCancel, submitAllowed, mobile, loadFailure }
    })

    assert.deepEqual(result.afterAvatar, { avatar: "replace", cover: "" })
    assert.deepEqual(result.afterCoverCancel, { avatar: "replace", cover: "" })
    assert.equal(result.submitAllowed, true)
    assert.ok(result.mobile.documentWidth <= result.mobile.viewport, JSON.stringify(result.mobile))
    result.mobile.editorWidths.forEach((width) => assert.ok(width <= result.mobile.viewport))
    assert.equal(result.loadFailure.operation, "")
    assert.equal(result.loadFailure.preview, true)
    assert.equal(result.loadFailure.workspace, false)
    assert.match(result.loadFailure.status, /編集元画像を読み込めませんでした/)
    assert.deepEqual(environment.errors, [])
  } finally {
    await environment?.close()
    await browser.close()
  }
})
