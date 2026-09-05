const MAX_BYTES = 20 * 1024 ** 2
const TIMEOUT_MS = 30_000
const HEIF_BRANDS = new Set(["heic", "heix", "hevc", "hevx", "mif1", "msf1"])

export function heifBrand(buffer) {
  const bytes = new Uint8Array(buffer)
  const text = (offset) => String.fromCharCode(...bytes.subarray(offset, offset + 4))
  if (bytes.length < 16 || text(4) !== "ftyp") return null
  const length = new DataView(buffer).getUint32(0)
  if (length < 16 || length > bytes.length || length % 4 !== 0) return null
  const brands = [text(8)]
  for (let offset = 16; offset < length; offset += 4) brands.push(text(offset))
  if (brands.some((brand) => brand === "avif" || brand === "avis")) return null
  return brands.find((brand) => HEIF_BRANDS.has(brand)) || null
}

export function isHeicNamed(file) {
  return /^image\/(heic|heif)(-sequence)?$/i.test(file.type) || /\.hei[cf]$/i.test(file.name)
}

export class ImageHeicConverter {
  constructor({ workerUrl, decoderUrl } = {}) {
    this.workerUrl = workerUrl
    this.decoderUrl = decoderUrl
    this.abortController = null
  }

  async prepare(file) {
    this.cancel()
    const abortController = new AbortController()
    this.abortController = abortController
    try {
      return await prepareHeicInput(file, {
        workerUrl: this.workerUrl,
        decoderUrl: this.decoderUrl,
        signal: abortController.signal,
        mode: "worker",
        limitMode: "large",
      })
    } finally {
      if (this.abortController === abortController) this.abortController = null
    }
  }

  cancel() {
    this.abortController?.abort()
    this.abortController = null
  }
}

function aborted() { return new DOMException("変換を中止しました。", "AbortError") }

export function convertInWorker(buffer, { workerUrl, decoderUrl, signal, limitMode = "standard", timeoutMs = TIMEOUT_MS }) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) { reject(aborted()); return }
    let worker
    let timer
    let settled = false
    const finish = (error, result) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      signal?.removeEventListener("abort", cancel)
      worker?.terminate()
      if (error) reject(error)
      else resolve(result)
    }
    const cancel = () => finish(aborted())
    try {
      worker = new Worker(workerUrl, { type: "module" })
      signal?.addEventListener("abort", cancel, { once: true })
      worker.onmessage = ({ data }) => data.ok
        ? finish(null, data)
        : finish(new Error(data.error || "HEIC / HEIF変換に失敗しました。"))
      worker.onerror = () => finish(new Error("HEIC変換Workerを実行できません。読み込み制限・ブラウザの対応状況を確認してください。"))
      worker.onmessageerror = () => finish(new Error("HEIC変換結果を受け取れませんでした。"))
      timer = setTimeout(() => finish(new Error("HEIC変換が30秒を超えたため中止しました。小さい画像で試してください。")), timeoutMs)
      worker.postMessage({ buffer, decoderUrl, mode: "worker", limitMode }, [buffer])
    } catch (error) { finish(error) }
  })
}

export async function prepareHeicInput(file, { workerUrl, decoderUrl, signal, mode = "worker", limitMode = "standard" }) {
  if (signal?.aborted) throw aborted()
  if (!["worker", "main"].includes(mode)) throw new Error("HEIC変換方式が不正です。")
  if (!["standard", "large"].includes(limitMode)) throw new Error("HEICの上限設定が不正です。")
  if (!file.size || file.size > MAX_BYTES) throw new Error("空でない20MiB以下の画像を選択してください。")
  const header = await file.slice(0, 4096).arrayBuffer()
  if (signal?.aborted) throw aborted()
  const brand = heifBrand(header)
  if (!brand) {
    if (isHeicNamed(file)) throw new Error("HEIC / HEIFの実体を確認できません。対応外形式または破損ファイルです。")
    return { file, conversion: null }
  }
  if (![workerUrl, decoderUrl].every((url) => typeof url === "string" && url.length > 0)) {
    throw new Error("HEIC変換モジュールのURLを確認できません。")
  }
  const started = performance.now()
  const buffer = await file.arrayBuffer()
  if (signal?.aborted) throw aborted()
  let result
  if (mode === "main") {
    // Deliberately separate diagnostic path. Never silently fall back from Worker.
    const { convertHeicBuffer } = await import(workerUrl)
    result = await convertHeicBuffer({ buffer, decoderUrl, mode, limitMode, signal })
  } else {
    result = await convertInWorker(buffer, { workerUrl, decoderUrl, signal, limitMode })
  }
  if (signal?.aborted) throw aborted()
  if (result.rgbaBuffer) {
    const { encodeHeicRgba } = await import(workerUrl)
    if (signal?.aborted) throw aborted()
    result = await encodeHeicRgba(result, { limitMode })
  }
  if (signal?.aborted) throw aborted()
  if (result.blob?.type !== "image/jpeg") throw new Error("変換後のJPEGを確認できません。未変換画像は使用しません。")
  return {
    file: new File([result.blob], "heic-converted.jpg", { type: "image/jpeg" }),
    conversion: { ...result.report, input: { name: file.name, bytes: file.size, brand }, elapsedMilliseconds: Math.round((performance.now() - started) * 10) / 10 },
  }
}
