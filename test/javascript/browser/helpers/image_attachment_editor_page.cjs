const fs = require("node:fs")
const http = require("node:http")
const path = require("node:path")

const root = path.resolve(__dirname, "../../../..")
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")

async function openImageAttachmentEditorPage(browser, { strictCsp = false } = {}) {
  const html = `<!doctype html><html><head><meta charset="utf-8">
    <style>
      [hidden] { display: none !important; }
      .editor { width: min(800px, 100%); height: 500px; }
      [data-image-attachment-editor-target~="currentPreview"] { max-width: 100%; }
      cropper-canvas { width: 100%; height: 100%; }
    </style>
    <script type="importmap" nonce="heic-test">{"imports":{"@hotwired/stimulus":"/stimulus.js","cropperjs":"/cropper.js","image_attachments/cropper_editor":"/cropper_editor.js","image_attachments/source_normalizer":"/source_normalizer.js","image_attachments/heic_converter":"/heic_converter.js"}}</script>
    </head><body><script type="module" nonce="heic-test">
      import Controller from "/controller.js"

      const markup = (id = "component") => \`
        <form id="form">
          <section id="\${id}">
            <input type="file" data-image-attachment-editor-target="fileInput">
            <img hidden data-image-attachment-editor-target="currentPreview">
            <p data-image-attachment-editor-target="previewEmpty"></p>
            <p hidden data-image-attachment-editor-target="deletionNotice"></p>
            <button type="button" hidden data-image-attachment-editor-target="editButton"></button>
            <button type="button" hidden data-image-attachment-editor-target="deleteButton"></button>
            <button type="button" hidden data-image-attachment-editor-target="undoButton"></button>
            <div hidden data-image-attachment-editor-target="workspace">
              <div class="editor" data-image-attachment-editor-target="editor"><img data-image-attachment-editor-target="source"></div>
              <button type="button" disabled data-image-attachment-editor-target="editorControl"></button>
              <button type="button" disabled data-image-attachment-editor-target="editorControl applyButton"></button>
            </div>
            <p hidden data-image-attachment-editor-target="warning"></p>
            <p tabindex="-1" data-image-attachment-editor-target="status"></p>
            <input type="hidden" name="image[operation]" data-image-attachment-editor-target="operationInput">
            <input type="file" name="image[source]" hidden data-image-attachment-editor-target="sourceInput">
            <input type="file" name="image[display]" hidden data-image-attachment-editor-target="displayInput">
            <input type="hidden" name="image[crop_data]" data-image-attachment-editor-target="cropDataInput">
          </section>
        </form>\`

      const buildController = (element, options = {}) => {
        const controller = new Controller()
        controller.element = element
        for (const name of Controller.targets) {
          const elements = controller.element.querySelectorAll('[data-image-attachment-editor-target~="' + name + '"]')
          controller[name + "Target"] = elements[0]
          controller[name + "Targets"] = Array.from(elements)
          controller["has" + name[0].toUpperCase() + name.slice(1) + "Target"] = elements.length > 0
        }
        controller.ratioKeyValue = options.ratioKey || "square"
        controller.currentSourceUrlValue = options.currentSourceUrl || ""
        controller.currentDisplayUrlValue = options.currentDisplayUrl || ""
        controller.currentCropDataValue = options.currentCropData || ""
        controller.currentSourceBlobIdValue = options.currentSourceBlobId || 0
        controller.keepStagedActionsValue = options.keepStagedActions || false
        controller.heicWorkerUrlValue = new URL("/worker.js", location).href
        controller.heicDecoderUrlValue = new URL("/decoder.js", location).href
        controller.hasCurrentSourceUrlValue = !!options.currentSourceUrl
        controller.hasCurrentDisplayUrlValue = !!options.currentDisplayUrl
        controller.hasCurrentCropDataValue = !!options.currentCropData
        controller.hasCurrentSourceBlobIdValue = Number.isSafeInteger(options.currentSourceBlobId) && options.currentSourceBlobId > 0
        controller.hasKeepStagedActionsValue = options.keepStagedActions === true
        controller.connect()
        return controller
      }

      window.mountEditor = (options = {}) => {
        window.editor?.disconnect()
        window.editors?.forEach((controller) => controller.disconnect())
        document.querySelector("#form")?.remove()
        document.body.insertAdjacentHTML("afterbegin", markup())
        const controller = buildController(document.querySelector("#component"), options)
        window.editor = controller
        window.editors = null
        return controller
      }

      window.mountEditors = (options) => {
        window.editor?.disconnect()
        window.editors?.forEach((controller) => controller.disconnect())
        document.querySelector("#form")?.remove()
        document.body.insertAdjacentHTML("afterbegin", markup("component-0"))
        const form = document.querySelector("#form")
        const template = document.createElement("template")
        template.innerHTML = markup("component-1")
        form.append(template.content.querySelector("section"))
        window.editor = null
        window.editors = options.map((value, index) => buildController(
          document.querySelector("#component-" + index),
          value
        ))
        return window.editors
      }

      window.imageFile = async ({ width, height, type = "image/png", name = "input.png" }) => {
        const canvas = document.createElement("canvas")
        canvas.width = width
        canvas.height = height
        const context = canvas.getContext("2d")
        context.fillStyle = "rgb(20, 80, 160)"
        context.fillRect(0, 0, width, height)
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, type, 0.94))
        canvas.width = 0
        canvas.height = 0
        return new File([blob], name, { type })
      }

      window.currentImage = async ({ ratioKey = "social", sourceBlobId = 42, stateSourceBlobId = sourceBlobId } = {}) => {
        const file = await window.imageFile({ width: 1421, height: 800, type: "image/jpeg", name: "source.jpg" })
        const sourceUrl = URL.createObjectURL(file)
        const displayUrl = URL.createObjectURL(file)
        const crop = ratioKey === "square"
          ? { x: 310.5, y: 0, width: 800, height: 800 }
          : { x: 100, y: 100, width: 1200, height: 630 }
        const output = ratioKey === "square"
          ? { width: 1024, height: 1024, mimeType: "image/jpeg", quality: 0.9 }
          : { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 }
        const state = {
          schemaVersion: 1,
          ratioKey,
          sourceBlobId: stateSourceBlobId,
          source: { width: 1421, height: 800 },
          crop,
          zoom: Math.round((1421 / crop.width) * 10000) / 10000,
          output,
        }
        return {
          currentSourceUrl: sourceUrl,
          currentDisplayUrl: displayUrl,
          currentCropData: JSON.stringify(state),
          currentSourceBlobId: sourceBlobId,
          ratioKey,
        }
      }

      window.mountEditor({ ratioKey: "square" })
      window.ready = true
    </script></body></html>`
  const scripts = {
    "/controller.js": "app/javascript/controllers/image_attachment_editor_controller.js",
    "/cropper_editor.js": "app/javascript/image_attachments/cropper_editor.js",
    "/source_normalizer.js": "app/javascript/image_attachments/source_normalizer.js",
    "/heic_converter.js": "app/javascript/image_attachments/heic_converter.js",
    "/worker.js": "app/javascript/image_attachments/heic_worker.js",
    "/decoder.js": "node_modules/heic-to/src/lib/libheif-without-unsafe-eval.js",
    "/cropper.js": "node_modules/cropperjs/dist/cropper.esm.js",
  }
  const requests = []
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, "http://127.0.0.1").pathname
    requests.push(pathname)
    if (strictCsp) response.setHeader("Content-Security-Policy", "default-src 'none'; script-src 'self' 'nonce-heic-test'; worker-src 'self'; connect-src 'self'; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'")
    if (pathname === "/") {
      response.setHeader("Content-Type", "text/html; charset=utf-8")
      response.end(html)
    } else if (pathname === "/stimulus.js") {
      response.setHeader("Content-Type", "text/javascript")
      response.end(`export class Controller {
        dispatch(name, { detail } = {}) {
          const event = new CustomEvent("image-attachment-editor:" + name, { bubbles: true, detail })
          this.element.dispatchEvent(event)
          return event
        }
      }`)
    } else if (scripts[pathname]) {
      response.setHeader("Content-Type", "text/javascript")
      response.end(read(scripts[pathname]))
    } else if (pathname.startsWith("/heic/")) {
      const filename = path.basename(pathname)
      const allowed = new Set(["medium.heic", "photo-24mp.heic"])
      if (!allowed.has(filename)) { response.writeHead(404); response.end(); return }
      response.setHeader("Content-Type", "image/heic")
      response.end(fs.readFileSync(path.join(root, "test/fixtures/files/heic", filename)))
    } else {
      response.writeHead(404)
      response.end()
    }
  })
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve))
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}/`)
    await page.waitForFunction(() => window.ready)
    return {
      page,
      errors,
      requests,
      close: async () => {
        await page.close()
        await new Promise((resolve) => server.close(resolve))
      },
    }
  } catch (error) {
    await page.close()
    await new Promise((resolve) => server.close(resolve))
    throw error
  }
}

module.exports = { openImageAttachmentEditorPage }
