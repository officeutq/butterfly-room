const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const controllerPath = path.resolve(
  __dirname,
  "../../app/javascript/controllers/image_upload_controller.js"
)

function loadController() {
  const timers = new Map()
  const logs = []
  let nextTimerId = 1
  let source = fs.readFileSync(controllerPath, "utf8")

  source = source.replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}"
  )
  source = source.replace(
    "export default class extends Controller",
    "globalThis.ImageUploadController = class extends Controller"
  )

  const window = { location: { href: "https://example.test/profile/edit" } }
  const context = vm.createContext({
    URL,
    Promise,
    console: { log: (...args) => logs.push(args) },
    window,
    setTimeout(callback, delay) {
      const id = nextTimerId
      nextTimerId += 1
      timers.set(id, { callback, delay })
      return id
    },
    clearTimeout(id) {
      timers.delete(id)
    },
  })

  vm.runInContext(source, context, { filename: controllerPath })

  return {
    Controller: context.ImageUploadController,
    logs,
    timers,
    window,
    runNextTimer() {
      const next = timers.entries().next()
      assert.equal(next.done, false, "expected a pending timer")

      const [id, timer] = next.value
      timers.delete(id)
      timer.callback()
      return timer.delay
    },
  }
}

function buildController(Controller, overrides = {}) {
  return Object.assign(
    new Controller(),
    {
      hasInitialUrlValue: false,
      initialUrlValue: "",
      hasInputTarget: true,
      inputTarget: { name: "image" },
      hasRemoveFlagTarget: true,
      removeFlagTarget: { value: "0" },
      hasErrorTarget: true,
      errorTarget: { hidden: true, textContent: "" },
      widthValue: 1920,
      heightValue: 1080,
    },
    overrides
  )
}

function buildPond(overrides = {}) {
  const handlers = {}
  let files = []

  return Object.assign(
    {
      handlers,
      on(eventName, handler) {
        handlers[eventName] = handler
      },
      addFile() {
        return Promise.resolve()
      },
      destroy() {},
      getFiles() {
        return files
      },
      removeFile() {
        files = []
        return Promise.resolve()
      },
      setFiles(nextFiles) {
        files = nextFiles
      },
    },
    overrides
  )
}

function installFilePond(window, pond, { includeTypePlugin = true } = {}) {
  const calls = { create: [], registerPlugin: [] }

  window.FilePond = {
    create(input, options) {
      calls.create.push({ input, options })
      return pond
    },
    registerPlugin(plugin) {
      calls.registerPlugin.push(plugin)
    },
  }
  window.FilePondPluginImagePreview = { name: "preview" }
  window.FilePondPluginImageResize = { name: "resize" }
  window.FilePondPluginImageTransform = { name: "transform" }
  if (includeTypePlugin) {
    window.FilePondPluginFileValidateType = { name: "validate-type" }
  }

  return calls
}

function flushPromises() {
  return new Promise((resolve) => setImmediate(resolve))
}

test("waits for every FilePond plugin and enables type validation", async () => {
  const environment = loadController()
  const pond = buildPond()
  const calls = installFilePond(environment.window, pond, { includeTypePlugin: false })
  const controller = buildController(environment.Controller)

  controller.connect()

  assert.equal(environment.runNextTimer(), 0)
  assert.equal(calls.create.length, 0)
  assert.equal(controller.setupAttempts, 1)

  environment.window.FilePondPluginFileValidateType = { name: "validate-type" }

  assert.equal(environment.runNextTimer(), 50)
  assert.equal(calls.create.length, 1)
  assert.deepEqual(
    calls.registerPlugin.map((plugin) => plugin.name),
    ["validate-type", "preview", "resize", "transform"]
  )

  const options = calls.create[0].options
  assert.deepEqual(Array.from(options.acceptedFileTypes), [
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
  ])
  assert.equal(options.labelFileTypeNotAllowed, "対応していない画像形式です")
  assert.match(options.fileValidateTypeLabelExpectedTypes, /HEIC \/ HEIF/)
  assert.equal(options.imageTransformOutputMimeType, "image/jpeg")
  assert.equal(
    await options.fileValidateTypeDetectType({ name: "camera.HEIC" }, ""),
    "image/heic"
  )
  assert.equal(
    await options.fileValidateTypeDetectType(
      { name: "camera.heif" },
      "application/octet-stream"
    ),
    "image/heif"
  )
  assert.equal(
    await options.fileValidateTypeDetectType({ name: "document.pdf" }, "application/pdf"),
    "application/pdf"
  )
})

test("disconnect clears a pending retry and destroys the FilePond instance", () => {
  const waitingEnvironment = loadController()
  const waitingController = buildController(waitingEnvironment.Controller)

  waitingController.connect()
  waitingEnvironment.runNextTimer()
  assert.equal(waitingEnvironment.timers.size, 1)

  waitingController.disconnect()
  assert.equal(waitingEnvironment.timers.size, 0)

  const readyEnvironment = loadController()
  let destroyCount = 0
  const pond = buildPond({ destroy: () => { destroyCount += 1 } })
  installFilePond(readyEnvironment.window, pond)
  const readyController = buildController(readyEnvironment.Controller)

  readyController.connect()
  readyEnvironment.runNextTimer()
  readyController.disconnect()

  assert.equal(destroyCount, 1)
  assert.equal(readyController.pond, null)
})

test("loads an existing image once when the initial request succeeds", async () => {
  const environment = loadController()
  const sources = []
  const pond = buildPond({
    addFile(source) {
      sources.push(source)
      return Promise.resolve()
    },
  })
  const controller = buildController(environment.Controller, {
    initialUrlValue: "/rails/active_storage/initial.jpg",
    pond,
    isDisconnected: false,
    initialFileRetryAttempted: false,
  })

  controller.loadInitialFile()
  await flushPromises()

  assert.deepEqual(sources, ["/rails/active_storage/initial.jpg"])
  assert.equal(controller.initialFileRetryAttempted, false)
})

test("retries a failed initial image once with cache busting without marking it for removal", async () => {
  const environment = loadController()
  const initialUrl = "/rails/active_storage/initial.jpg?disposition=inline"
  const sources = []
  const removed = []
  let files = [{ id: "initial-file", source: initialUrl }]
  const pond = buildPond({
    addFile(source) {
      sources.push(source)
      return sources.length === 1
        ? Promise.reject(new Error("initial load failed"))
        : Promise.resolve()
    },
    getFiles() {
      return files
    },
    removeFile(fileId, options) {
      removed.push({ fileId, options })
      files = []
      return Promise.resolve()
    },
  })
  const controller = buildController(environment.Controller, {
    hasInitialUrlValue: true,
    initialUrlValue: initialUrl,
    hadInitialFile: true,
    pond,
    isDisconnected: false,
    initialFileRetryAttempted: false,
    suppressRemoveFlagUpdate: false,
  })

  controller.loadInitialFile()
  await flushPromises()
  await flushPromises()

  assert.equal(sources.length, 2)
  assert.equal(sources[0], initialUrl)
  assert.match(sources[1], /image_upload_cache_bust=/)
  assert.equal(removed.length, 1)
  assert.equal(removed[0].fileId, "initial-file")
  assert.equal(removed[0].options.revert, false)
  assert.equal(controller.removeFlagTarget.value, "0")
  assert.equal(controller.initialFileRetryAttempted, true)

  await controller.retryInitialFileLoad()
  assert.equal(sources.length, 2)
})

test("keeps the removal flag clear when both initial image loads fail", async () => {
  const environment = loadController()
  const pond = buildPond({
    addFile() {
      return Promise.reject(new Error("load failed"))
    },
  })
  const controller = buildController(environment.Controller, {
    initialUrlValue: "/rails/active_storage/initial.jpg",
    pond,
    isDisconnected: false,
    initialFileRetryAttempted: false,
    suppressRemoveFlagUpdate: false,
  })

  controller.loadInitialFile()
  await flushPromises()
  await flushPromises()

  assert.equal(controller.removeFlagTarget.value, "0")
  assert.equal(controller.initialFileRetryAttempted, true)
})

test("updates the removal flag for deletion, addition, and replacement", () => {
  const environment = loadController()
  const pond = buildPond()
  const controller = buildController(environment.Controller, {
    hadInitialFile: true,
    pond,
    suppressRemoveFlagUpdate: false,
  })

  controller.bindEvents()

  pond.handlers.addfile(
    { main: "対応していない画像形式です", sub: "JPEGを選択してください" },
    null,
    null
  )
  assert.equal(controller.errorTarget.hidden, false)
  assert.match(controller.errorTarget.textContent, /対応していない画像形式/)

  pond.handlers.addfile(null, { id: "new-file" }, null)
  assert.equal(controller.errorTarget.hidden, true)
  assert.equal(controller.errorTarget.textContent, "")

  pond.setFiles([])
  pond.handlers.removefile()
  assert.equal(controller.removeFlagTarget.value, "1")

  pond.handlers.addfile()
  assert.equal(controller.removeFlagTarget.value, "0")

  pond.setFiles([{ id: "replacement" }])
  pond.handlers.removefile()
  assert.equal(controller.removeFlagTarget.value, "0")

  controller.hadInitialFile = false
  pond.setFiles([])
  pond.handlers.removefile()
  assert.equal(controller.removeFlagTarget.value, "0")

  controller.suppressRemoveFlagUpdate = true
  controller.removeFlagTarget.value = "0"
  pond.handlers.removefile()
  assert.equal(controller.removeFlagTarget.value, "0")
})
