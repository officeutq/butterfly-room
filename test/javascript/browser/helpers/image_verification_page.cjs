const fs = require("node:fs")
const path = require("node:path")
const http = require("node:http")

const root = path.resolve(__dirname, "../../../..")
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")

async function openVerificationPage(browser, { strictCsp = false } = {}) {
  const view = read("app/views/system_admin/image_upload_verifications/show.html.erb").replace(/<%[\s\S]*?%>/g, "")
  const html = `<!doctype html><html><head><meta charset="utf-8">
    <style>.image-upload-verification__editor { width: 800px; height: 500px; } cropper-canvas { width: 100%; height: 100%; } [hidden] { display: none !important; }</style>
    <script type="importmap" nonce="heic-test">{"imports":{"@hotwired/stimulus":"/stimulus.js","cropperjs":"/cropper.js","controllers/image_upload_verification/source_normalizer":"/source_normalizer.js","controllers/image_upload_verification/heic_converter":"/heic_converter.js"}}</script>
    </head><body>${view}<script type="module" nonce="heic-test">
    import Controller from "/controller.js"
    import { prepareHeicInput, convertInWorker } from "/heic_converter.js"
    window.prepareHeicInput = prepareHeicInput
    window.convertInWorker = convertInWorker
    const controller = new Controller()
    for (const name of Controller.targets) {
      const elements = document.querySelectorAll('[data-image-upload-verification-target="' + name + '"]')
      controller[name + "Target"] = elements[0]
      controller[name + "Targets"] = Array.from(elements)
    }
    controller.heicWorkerUrlValue = new URL("/worker.js", location).href
    controller.heicDecoderUrlValue = new URL("/decoder.js", location).href
    controller.connect()
    window.verification = controller
    </script></body></html>`
  const scripts = {
    "/controller.js": "app/javascript/controllers/image_upload_verification_controller.js",
    "/source_normalizer.js": "app/javascript/controllers/image_upload_verification/source_normalizer.js",
    "/heic_converter.js": "app/javascript/controllers/image_upload_verification/heic_converter.js",
    "/worker.js": "app/javascript/image_upload_verification/heic_worker.js",
    "/decoder.js": "node_modules/heic-to/src/lib/libheif-without-unsafe-eval.js",
    "/cropper.js": "node_modules/cropperjs/dist/cropper.esm.js",
  }
  const requests = []
  const fixtures = new Set(["medium.heic", "large.heic", "photo-24mp.heic", "rotated.heif", "alpha.heic", "multiple.heic"])
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, "http://127.0.0.1").pathname
    requests.push(pathname)
    if (strictCsp) response.setHeader("Content-Security-Policy", "default-src 'none'; script-src 'self' 'nonce-heic-test'; worker-src 'self'; connect-src 'self' blob:; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'")
    if (pathname === "/") { response.setHeader("Content-Type", "text/html; charset=utf-8"); response.end(html) }
    else if (pathname === "/stimulus.js") { response.setHeader("Content-Type", "text/javascript"); response.end("export class Controller {}") }
    else if (scripts[pathname]) { response.setHeader("Content-Type", "text/javascript"); response.end(read(scripts[pathname])) }
    else if (pathname === "/sample.heic") { response.end(fs.readFileSync(path.join(root, "test/fixtures/files/sample.heic"))) }
    else if (pathname.startsWith("/heic/") && fixtures.has(pathname.slice(6))) { response.end(fs.readFileSync(path.join(root, "test/fixtures/files/heic", pathname.slice(6)))) }
    else { response.writeHead(404); response.end() }
  })
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve))
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } })
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}/`)
    await page.waitForFunction(() => !!window.verification)
    return { page, errors, requests, close: async () => { await page.close(); await new Promise((resolve) => server.close(resolve)) } }
  } catch (error) {
    await page.close()
    await new Promise((resolve) => server.close(resolve))
    throw error
  }
}

module.exports = { openVerificationPage }
