const REQUEST_TIMEOUT = 120_000
const LIMITS = { source: 20 * 1024 ** 2, display: 5 * 1024 ** 2 }

export function validateUploadPair({ source, display, cropData }) {
  for (const [role, blob] of Object.entries({ source, display })) {
    if (!blob || blob.type !== "image/jpeg" || blob.size <= 0 || blob.size > LIMITS[role]) {
      throw new Error(`${role}のJPEG容量が暫定上限を超えています（編集元20MiB・表示用5MiB）。`)
    }
  }
  if (!cropData) throw new Error("クロップ状態を取得できません。")
}

// A retry always starts a new owned run. Never reuse a partially uploaded pair.
export class UploadVerificationClient {
  constructor({ url, onProgress = () => {}, directUploadClass = null }) {
    this.url = url
    this.onProgress = onProgress
    this.directUploadClass = directUploadClass
    this.requests = new Set()
    this.canceled = false
    this.run = null
  }

  async upload(pair, transport) {
    validateUploadPair(pair)
    if (!["multipart", "direct"].includes(transport)) throw new Error("送信方式が不正です。")
    const started = performance.now()
    try {
      this.run = await this.request("POST", this.url, {
        verification: { transport, crop_data: pair.cropData },
      })
      this.checkCanceled()
      const base = `${this.url}/${this.run.id}`
      let report
      if (transport === "multipart") {
        const body = new FormData()
        body.append("verification[source]", pair.source, "source.jpg")
        body.append("verification[display]", pair.display, "display.jpg")
        report = await this.request("POST", `${base}/multipart`, body, "2画像を一括送信")
      } else if (transport === "direct") {
        // Rails' public DirectUpload API computes MD5 and sends the signed PUT.
        const DirectUpload = this.directUploadClass || (await import("@rails/activestorage")).DirectUpload
        this.checkCanceled()
        const signedIds = {}
        for (const role of ["source", "display"]) {
          signedIds[role] = await this.direct(DirectUpload, pair[role], `${base}/direct_upload/${role}`, role)
        }
        report = await this.request("POST", `${base}/complete`, { verification: signedIds }, "保存先の実体を確認")
      } else {
        throw new Error("送信方式が不正です。")
      }
      this.checkCanceled()
      return { ...report, client_milliseconds: Math.round((performance.now() - started) * 10) / 10,
        crop_data: pair.cropData, user_agent: navigator.userAgent }
    } catch (error) {
      this.cancel()
      throw error
    }
  }

  request(method, url, body, label = "検証を準備") {
    this.checkCanceled()
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      this.track(xhr)
      xhr.open(method, url)
      xhr.timeout = REQUEST_TIMEOUT
      xhr.setRequestHeader("Accept", "application/json")
      xhr.setRequestHeader("X-CSRF-Token", this.csrfToken())
      if (!(body instanceof FormData)) xhr.setRequestHeader("Content-Type", "application/json")
      xhr.upload.onprogress = (event) => this.progress(label, event)
      xhr.onload = () => {
        let result
        try { result = JSON.parse(xhr.responseText) } catch { /* login/edge error HTML is not a successful upload */ }
        if (xhr.status >= 200 && xhr.status < 300 && result) resolve(result)
        else reject(new Error(result?.error || `送信に失敗しました（HTTP ${xhr.status}）。ログイン状態や容量制限を確認してください。`))
      }
      xhr.onerror = () => reject(new Error("通信に失敗しました。接続を確認し、新しく検証を開始してください。"))
      xhr.ontimeout = () => reject(new Error("送信・確認が120秒でタイムアウトしました。新しく検証を開始してください。"))
      xhr.onabort = () => reject(new Error("送信を中止しました。"))
      this.onProgress(label, null)
      xhr.send(body instanceof FormData ? body : JSON.stringify(body))
    })
  }

  direct(DirectUpload, blob, url, role) {
    this.checkCanceled()
    return new Promise((resolve, reject) => {
      let settled = false
      const finish = (error, result) => {
        if (settled) return
        settled = true
        error ? reject(new Error(String(error))) : resolve(result.signed_id)
      }
      const prepare = (xhr, label) => {
        this.track(xhr)
        xhr.timeout = REQUEST_TIMEOUT
        xhr.addEventListener("timeout", () => finish("直接送信が120秒でタイムアウトしました。"))
        xhr.addEventListener("abort", () => finish("送信を中止しました。"))
        xhr.upload.addEventListener("progress", (event) => this.progress(label, event))
        // DirectUpload calls this hook before xhr.send. Abort after send when
        // cancellation occurred during its asynchronous checksum computation.
        if (this.canceled) {
          finish("送信を中止しました。")
          queueMicrotask(() => xhr.abort())
        }
      }
      const upload = new DirectUpload(new File([blob], `${role}.jpg`, { type: "image/jpeg" }), url, {
        directUploadWillCreateBlobWithXHR: (xhr) => prepare(xhr, `${role}の送信を準備`),
        directUploadWillStoreFileWithXHR: (xhr) => prepare(xhr, `${role}を保存先へ直接送信`),
      })
      upload.create((error, result) => {
        // The public library's error includes a filename (ours is fixed).
        if (error) finish(`${role}の直接送信に失敗しました。S3のPUT・CORS設定、接続、容量を確認してください。`)
        else if (this.canceled) finish("送信を中止しました。")
        else finish(null, result)
      })
    })
  }

  track(xhr) {
    this.requests.add(xhr)
    xhr.addEventListener("loadend", () => this.requests.delete(xhr), { once: true })
  }

  progress(label, event) {
    if (!this.canceled) this.onProgress(label, event.lengthComputable ? Math.round(event.loaded / event.total * 100) : null)
  }

  checkCanceled() {
    if (this.canceled) throw new Error("送信を中止しました。")
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  cancel() {
    this.canceled = true
    for (const xhr of this.requests) xhr.abort()
    this.requests.clear()
    if (!this.run || this.cancelRequested) return
    this.cancelRequested = true
    // Best effort only. The scheduled sweep also handles lost responses,
    // closed tabs, offline cancellation and disabled feature flags.
    fetch(`${this.url}/${this.run.id}`, { method: "DELETE", credentials: "same-origin", keepalive: true,
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" } }).catch(() => {})
  }
}
