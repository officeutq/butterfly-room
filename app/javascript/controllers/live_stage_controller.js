import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // viewer / live ともにスクロールを殺す
    this._prevHtmlOverflow = document.documentElement.style.overflow
    this._prevBodyOverflow = document.body.style.overflow
    document.documentElement.style.overflow = "hidden"
    document.body.style.overflow = "hidden"

    this._update = this._update.bind(this)

    this._vv = window.visualViewport || null
    this._keyboardThresholdPx = 120
    this._lastNonKeyboardViewportH = this._currentViewportHeight()
    this._keyboardOpen = false

    window.addEventListener("resize", this._update)
    window.addEventListener("orientationchange", this._update)
    document.addEventListener("focusin", this._update)
    document.addEventListener("focusout", this._update)

    if (this._vv) {
      this._vv.addEventListener("resize", this._update)
      this._vv.addEventListener("scroll", this._update)
    }

    requestAnimationFrame(() => this._update())
  }

  disconnect() {
    window.removeEventListener("resize", this._update)
    window.removeEventListener("orientationchange", this._update)
    document.removeEventListener("focusin", this._update)
    document.removeEventListener("focusout", this._update)

    if (this._vv) {
      this._vv.removeEventListener("resize", this._update)
      this._vv.removeEventListener("scroll", this._update)
    }

    document.body.classList.remove("keyboard-open", "cast-live-keyboard-open")
    document.documentElement.style.overflow = this._prevHtmlOverflow
    document.body.style.overflow = this._prevBodyOverflow

    document.documentElement.style.removeProperty("--soft-keyboard-inset-h")
    document.documentElement.style.removeProperty("--keyboard-visible-viewport-h")
  }

  onCommentSubmitStart(_event) {
    // まずは何もしない。
    // iPhone Safari 向けの blur 制御が必要なら次段で追加する。
  }

  onCommentSubmitEnd(_event) {
    // 送信後の scrollTo(0, 0) は行わず、
    // Safari の viewport 変動が落ち着くのを待ちながら再計算だけ行う。
    requestAnimationFrame(() => this._update())
    requestAnimationFrame(() => {
      requestAnimationFrame(() => this._update())
    })

    ;[100, 250, 400].forEach((delayMs) => {
      window.setTimeout(() => this._update(), delayMs)
    })
  }

  _update() {
    const header = document.getElementById("app_header")
    const footer = document.getElementById("app_footer")
    const isCastLiveLayout = document.body.classList.contains("cast-live-layout")

    const headerH = header ? header.getBoundingClientRect().height : 0
    const footerH = footer ? footer.getBoundingClientRect().height : 0

    const currentViewportH = this._currentViewportHeight()
    const safeViewportH = Math.max(0, Math.round(currentViewportH))
    const safeHeaderH = Math.max(0, Math.round(headerH))
    const safeFooterH = Math.max(0, Math.round(footerH))

    const rawKeyboardInsetH = this._keyboardInsetHeight()
    const nextKeyboardOpen = this._isKeyboardOpen(currentViewportH)

    if (this._canCaptureNonKeyboardViewportHeight(currentViewportH, nextKeyboardOpen, rawKeyboardInsetH)) {
      this._lastNonKeyboardViewportH = currentViewportH
    }

    // cast/live ではキーボード中も stage/media 側は動かさない
    const liveStageHBase = isCastLiveLayout && nextKeyboardOpen
      ? this._lastNonKeyboardViewportH
      : currentViewportH

    const liveStageH = Math.max(0, Math.round(liveStageHBase))
    const viewerStageH = Math.max(0, safeViewportH - safeHeaderH - safeFooterH)

    const keyboardInsetH = nextKeyboardOpen ? rawKeyboardInsetH : 0
    const keyboardVisibleViewportH = nextKeyboardOpen
      ? Math.max(0, Math.round(currentViewportH))
      : 0

    this._keyboardOpen = nextKeyboardOpen

    document.body.classList.toggle("keyboard-open", nextKeyboardOpen)
    document.body.classList.toggle("cast-live-keyboard-open", nextKeyboardOpen && isCastLiveLayout)

    document.documentElement.style.setProperty("--live-stage-h", `${liveStageH}px`)
    document.documentElement.style.setProperty("--viewer-stage-h", `${viewerStageH}px`)
    document.documentElement.style.setProperty("--app-header-h", `${safeHeaderH}px`)
    document.documentElement.style.setProperty("--app-footer-h", `${safeFooterH}px`)
    document.documentElement.style.setProperty("--soft-keyboard-inset-h", `${Math.max(0, Math.round(keyboardInsetH))}px`)
    document.documentElement.style.setProperty("--keyboard-visible-viewport-h", `${keyboardVisibleViewportH}px`)
  }

  _canCaptureNonKeyboardViewportHeight(currentViewportH, nextKeyboardOpen, keyboardInsetH) {
    if (nextKeyboardOpen) return false

    const lastViewportH = this._lastNonKeyboardViewportH || 0
    if (lastViewportH <= 0) return true

    // keyboard が閉じ切る前の縮んだ高さで
    // 「通常時の高さ」を上書きしない
    if (keyboardInsetH > 0) {
      const recoveryAllowancePx = Math.max(24, Math.floor(this._keyboardThresholdPx / 2))
      return currentViewportH >= (lastViewportH - recoveryAllowancePx)
    }

    return true
  }

  _currentViewportHeight() {
    return this._vv?.height || window.innerHeight || 0
  }

  _keyboardInsetHeight() {
    if (!this._vv) return 0

    const baseH = this._lastNonKeyboardViewportH || window.innerHeight || 0
    const vvHeight = this._vv.height || 0
    const vvOffsetTop = this._vv.offsetTop || 0

    return Math.max(0, baseH - vvHeight - vvOffsetTop)
  }

  _isKeyboardOpen(currentViewportH) {
    if (!this._isMobileLike()) return false
    if (!this._hasTextInputFocus()) return false

    const baseH = this._lastNonKeyboardViewportH || currentViewportH
    const delta = Math.max(0, baseH - currentViewportH)

    return delta >= this._keyboardThresholdPx
  }

  _isMobileLike() {
    return window.matchMedia("(pointer: coarse)").matches || window.innerWidth < 992
  }

  _hasTextInputFocus() {
    const active = document.activeElement
    if (!active) return false

    if (active.matches("textarea")) return true
    if (active.matches("[contenteditable='true']")) return true

    if (active.matches("input")) {
      const type = (active.getAttribute("type") || "text").toLowerCase()
      return ![
        "button",
        "checkbox",
        "color",
        "file",
        "hidden",
        "image",
        "radio",
        "range",
        "reset",
        "submit",
      ].includes(type)
    }

    return false
  }
}
