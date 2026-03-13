import { Controller } from "@hotwired/stimulus"
import { Dom, Effect, Module, Player, Webcam } from "banuba-web-sdk"

export default class extends Controller {
  static targets = ["surface", "error", "state", "startBtn", "stopBtn", "effectBtn"]

  static values = {
    clientToken: String,
    sdkBaseUrl: String,
    faceTrackerUrl: String,
    eyesUrl: String,
    lipsUrl: String,
    skinUrl: String,
    effectUrl: String,
    effectName: String,
  }

  connect() {
    this._player = null
    this._started = false

    this._beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this._beforeCache)

    this._setState("idle")
    this._syncUI()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this._beforeCache)
    this.stop()
  }

  async start() {
    if (this._started) return

    if (!this.clientTokenValue) {
      this._setError("BANUBA_CLIENT_TOKEN が未設定です。")
      return
    }

    this._clearError()
    this._setState("starting")

    try {
      const sdkBase = this._normalizedSdkBaseUrl()

      const player = await Player.create({
        clientToken: this.clientTokenValue,
        locateFile: {
          "BanubaSDK.data": `${sdkBase}/BanubaSDK.data`,
          "BanubaSDK.wasm": `${sdkBase}/BanubaSDK.wasm`,
          "BanubaSDK.simd.wasm": `${sdkBase}/BanubaSDK.simd.wasm`,
        },
      })

      const modules = [new Module(this.faceTrackerUrlValue)]

      if (this.eyesUrlValue) {
        modules.push(new Module(this.eyesUrlValue))
      }

      if (this.lipsUrlValue) {
        modules.push(new Module(this.lipsUrlValue))
      }

      if (this.skinUrlValue) {
        modules.push(new Module(this.skinUrlValue))
      }

      await player.addModule(...modules)
      await player.use(new Webcam())

      Dom.render(player, this.surfaceTarget)

      if (this.effectUrlValue) {
        player.applyEffect(new Effect(this.effectUrlValue))
      }

      this._player = player
      this._started = true
      this._setState("running")
    } catch (error) {
      console.error("[banuba-verification] start failed", error)
      this._setError(this._humanizeError(error))
      await this._destroyPlayer()
      this._setState("error")
    } finally {
      this._syncUI()
    }
  }

  async stop() {
    if (!this._player && !this._started) {
      this._setState("idle")
      this._syncUI()
      return
    }

    this._setState("stopping")

    try {
      await this._destroyPlayer()
      this._clearError()
      this._setState("idle")
    } catch (error) {
      console.error("[banuba-verification] stop failed", error)
      this._setError("停止処理でエラーが発生しました。再読込してください。")
      this._setState("error")
    } finally {
      this._syncUI()
    }
  }

  reapplyEffect() {
    if (!this._player) return
    if (!this.effectUrlValue) return

    try {
      this._player.applyEffect(new Effect(this.effectUrlValue))
      this._clearError()
      this._setState(`effect:${this.effectNameValue || "applied"}`)
    } catch (error) {
      console.error("[banuba-verification] effect apply failed", error)
      this._setError("effect の再適用に失敗しました。")
      this._setState("error")
    } finally {
      this._syncUI()
    }
  }

  async _destroyPlayer() {
    if (this._player) {
      try {
        if (typeof this._player.destroy === "function") {
          await this._player.destroy()
        }
      } catch (_) {
      }
    }

    this._player = null
    this._started = false

    if (this.hasSurfaceTarget) {
      this.surfaceTarget.innerHTML = ""
    }
  }

  _normalizedSdkBaseUrl() {
    return (this.sdkBaseUrlValue || "").replace(/\/+$/, "")
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

    if (this.hasEffectBtnTarget) {
      const visible = this._started && !!this.effectUrlValue
      this.effectBtnTarget.classList.toggle("d-none", !visible)
      this.effectBtnTarget.disabled = !visible
    }
  }

  _setState(state) {
    if (this.hasStateTarget) {
      this.stateTarget.textContent = state
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
    const message = `${error?.message || error}`

    if (error?.name === "NotAllowedError" || error?.name === "SecurityError") {
      return "カメラ権限が拒否されました。ブラウザ設定で許可してください。"
    }

    if (error?.name === "NotFoundError" || error?.name === "OverconstrainedError") {
      return "利用できるカメラが見つかりません。接続やOS設定を確認してください。"
    }

    if (error?.name === "NotReadableError") {
      return "カメラを使用できません。他アプリが使用中の可能性があります。"
    }

    return `Banuba の起動に失敗しました: ${message}`
  }
}
