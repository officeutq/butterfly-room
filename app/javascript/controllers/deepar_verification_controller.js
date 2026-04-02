import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",
    "error",
    "state",
    "faceState",
    "startBtn",
    "stopBtn",
    "effectLabel",
  ]

  static values = {
    licenseKey: String,
    rootPath: String,
    defaultEffectUrl: String,
  }

  connect() {
    this._deepAR = null
    this._started = false
    this._selectedEffectUrl = this.defaultEffectUrlValue || ""

    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)

    this._setState("idle")
    this._setFaceState("face: unknown")
    this._syncEffectLabel()
    this._syncUI()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    this.stop()
  }

  async start() {
    if (this._started) return

    if (!this.licenseKeyValue) {
      this._setError("DEEPAR_LICENSE_KEY が未設定です。")
      return
    }

    if (!window.deepar || typeof window.deepar.initialize !== "function") {
      this._setError("DeepAR SDK の読み込みに失敗しました。/deepar/js/deepar.js を確認してください。")
      this._setState("error")
      return
    }

    this._clearError()
    this._setState("starting")

    try {
      const deepAR = await window.deepar.initialize({
        licenseKey: this.licenseKeyValue,
        previewElement: this.previewTarget,
        effect: this._selectedEffectUrl,
        rootPath: this.rootPathValue,
      })

      if (deepAR?.callbacks) {
        deepAR.callbacks.onFaceVisibilityChanged = (visible) => {
          this._setFaceState(visible ? "face: visible" : "face: hidden")
        }
      }

      this._deepAR = deepAR
      this._started = true
      this._setState("running")
      this._clearError()
    } catch (error) {
      console.error("[deepar-verification] start failed", error)
      this._setError(this._humanizeError(error))
      this._setState("error")
      this._shutdown()
    } finally {
      this._syncUI()
    }
  }

  stop() {
    if (!this._deepAR && !this._started) {
      this._setState("idle")
      this._setFaceState("face: unknown")
      this._syncUI()
      return
    }

    this._setState("stopping")

    try {
      this._shutdown()
      this._clearError()
      this._setState("idle")
      this._setFaceState("face: unknown")
    } catch (error) {
      console.error("[deepar-verification] stop failed", error)
      this._setError("停止処理でエラーが発生しました。再読込してください。")
      this._setState("error")
    } finally {
      this._syncUI()
    }
  }

  async selectEffect(event) {
    const nextUrl = event.currentTarget?.dataset?.effectUrl
    if (!nextUrl) return

    this._selectedEffectUrl = nextUrl
    this._syncEffectLabel()
    this._syncEffectButtons(event.currentTarget)

    if (!this._deepAR) return

    this._clearError()
    this._setState("switching-effect")

    try {
      await this._deepAR.switchEffect(nextUrl)
      this._setState("running")
    } catch (error) {
      console.error("[deepar-verification] switchEffect failed", error)
      this._setError("effect の切替に失敗しました。")
      this._setState("error")
    } finally {
      this._syncUI()
    }
  }

  _shutdown() {
    if (this._deepAR && typeof this._deepAR.shutdown === "function") {
      this._deepAR.shutdown()
    }

    this._deepAR = null
    this._started = false

    if (this.hasPreviewTarget) {
      this.previewTarget.innerHTML = ""
    }
  }

  _syncUI() {
    if (this.hasStartBtnTarget) {
      this.startBtnTarget.classList.toggle("d-none", this._started)
      this.startBtnTarget.disabled = this._started
    }

    if (this.hasStopBtnTarget) {
      this.stopBtnTarget.classList.toggle("d-none", !this._started)
      this.stopBtnTarget.disabled = !this._started
    }
  }

  _syncEffectLabel() {
    if (this.hasEffectLabelTarget) {
      this.effectLabelTarget.textContent = this._selectedEffectUrl || "(none)"
    }
  }

  _syncEffectButtons(activeButton) {
    this.element.querySelectorAll("[data-effect-url]").forEach((button) => {
      const isActive = button === activeButton
      button.classList.toggle("btn-primary", isActive)
      button.classList.toggle("btn-outline-primary", !isActive)
    })
  }

  _setState(state) {
    if (this.hasStateTarget) {
      this.stateTarget.textContent = state
    }
  }

  _setFaceState(state) {
    if (this.hasFaceStateTarget) {
      this.faceStateTarget.textContent = state
    }
  }

  _clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
    }
  }

  _setError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
    }
  }

  _humanizeError(error) {
    const name = error?.name
    const message = `${error?.message || error}`

    if (name === "NotAllowedError" || name === "SecurityError") {
      return "カメラ権限が拒否されました。ブラウザ設定で許可してください。"
    }

    if (name === "NotFoundError" || name === "OverconstrainedError") {
      return "利用できるカメラが見つかりません。接続やOS設定を確認してください。"
    }

    if (name === "NotReadableError") {
      return "カメラを使用できません。他アプリが使用中の可能性があります。"
    }

    return `DeepAR の起動に失敗しました: ${message}`
  }
}
