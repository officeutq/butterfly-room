export const IMAGE_PAIR_MULTIPART_TIMEOUT_MS = 45_000

export class ImagePairMultipartError extends Error {
  constructor(message, { code = "upload_failed", status = null, retryable = false } = {}) {
    super(message)
    this.name = "ImagePairMultipartError"
    this.code = code
    this.status = status
    this.retryable = retryable
  }
}

// Sends one already-built FormData body. It deliberately does not retry
// automatically: a manual retry carries the same expected image IDs, allowing
// Rails to reject a late duplicate without combining two attempts.
export class ImagePairMultipartClient {
  constructor({ timeout = IMAGE_PAIR_MULTIPART_TIMEOUT_MS, xhrClass = XMLHttpRequest } = {}) {
    this.timeout = timeout
    this.xhrClass = xhrClass
    this.request = null
  }

  submit({ url, method = "PATCH", body }) {
    if (this.request) {
      return Promise.reject(new ImagePairMultipartError("画像を送信中です。"))
    }
    if (!(body instanceof FormData)) {
      return Promise.reject(new TypeError("body must be FormData"))
    }

    return new Promise((resolve, reject) => {
      const request = new this.xhrClass()
      this.request = request
      request.open(method, url)
      request.timeout = this.timeout
      request.setRequestHeader("Accept", "application/json")
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      if (csrfToken) request.setRequestHeader("X-CSRF-Token", csrfToken)

      request.onload = () => {
        const payload = parseJson(request.responseText)
        if (request.status >= 200 && request.status < 300) {
          if (request.status === 204 || (
            request.getResponseHeader("Content-Type")?.includes("application/json") && payload
          )) {
            resolve(payload || {})
          } else {
            reject(new ImagePairMultipartError(
              "保存結果を確認できませんでした。画面を読み直してください。",
              { code: "unexpected_response" }
            ))
          }
          return
        }

        reject(httpError(request.status, payload || {}))
      }
      request.onerror = () => reject(networkError())
      request.ontimeout = () => reject(new ImagePairMultipartError(
        "画像送信が45秒を超えました。再度保存してください。",
        { code: "upload_timeout", retryable: true }
      ))
      request.onabort = () => reject(new ImagePairMultipartError(
        "画像送信を中止しました。",
        { code: "upload_aborted", retryable: true }
      ))
      request.onloadend = () => {
        if (this.request === request) this.request = null
      }
      try {
        request.send(body)
      } catch (_) {
        if (this.request === request) this.request = null
        reject(networkError())
      }
    })
  }

  abort() {
    this.request?.abort()
  }
}

function parseJson(value) {
  if (!value) return null

  try {
    return JSON.parse(value)
  } catch (_) {
    return null
  }
}

function networkError() {
  return new ImagePairMultipartError(
    "通信に失敗しました。接続を確認して再度保存してください。",
    { code: "network_error", retryable: true }
  )
}

function httpError(status, payload) {
  const code = payload.error || `http_${status}`
  const retryable = payload.retryable === true || status === 413 || status >= 500
  const defaultMessage = status === 409
    ? "画像が別の画面で更新されています。読み直して編集してください。"
    : "画像を保存できませんでした。入力内容を確認してください。"
  return new ImagePairMultipartError(payload.message || defaultMessage, {
    code,
    status,
    retryable,
  })
}
