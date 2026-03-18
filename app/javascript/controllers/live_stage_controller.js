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
    this._lockedLiveStageH = Math.max(0, Math.round(this._lastNonKeyboardViewportH))
    this._lockedKeyboardInsetH = 0

    window.addEventListener("resize", this._update)
    window.addEventListener("orientationchange", this._update)
    document.addEventListener("focusin", this._update)
    document.addEventListener("focusout", this._update)

    if (this._vv) {
      this._vv.addEventListener("resize", this._update)
      this._vv.addEventListener("scroll", this._update)
    }

    this._lockPageScrollTop()
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
    this._lockPageScrollTop()
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

    const nextKeyboardOpen = this._isKeyboardOpen(currentViewportH)
    const rawKeyboardInsetH = this._keyboardInsetHeight()

    if (!nextKeyboardOpen) {
      this._lastNonKeyboardViewportH = currentViewportH
    }

    if (nextKeyboardOpen && !this._keyboardOpen) {
      // closed -> open に遷移した瞬間の値を固定
      this._lockedLiveStageH = Math.max(0, Math.round(this._lastNonKeyboardViewportH || currentViewportH))
      this._lockedKeyboardInsetH = Math.max(0, Math.round(rawKeyboardInsetH))
      this._lockPageScrollTop()
    } else if (!nextKeyboardOpen && this._keyboardOpen) {
      // open -> closed
      this._lockedKeyboardInsetH = 0
      this._lockPageScrollTop()
    } else if (!nextKeyboardOpen) {
      // 通常時は最新値へ追随
      this._lockedLiveStageH = Math.max(0, Math.round(currentViewportH))
      this._lockedKeyboardInsetH = 0
    }

    this._keyboardOpen = nextKeyboardOpen

    const liveStageH = isCastLiveLayout && this._keyboardOpen
      ? this._lockedLiveStageH
      : Math.max(0, Math.round(currentViewportH))

    const keyboardInsetH = isCastLiveLayout && this._keyboardOpen
      ? this._lockedKeyboardInsetH
      : Math.max(0, Math.round(rawKeyboardInsetH))

    // viewer は header / footer を除いた本文可視領域
    const viewerStageH = Math.max(0, safeViewportH - safeHeaderH - safeFooterH)

    document.body.classList.toggle("keyboard-open", this._keyboardOpen)
    document.body.classList.toggle("cast-live-keyboard-open", this._keyboardOpen && isCastLiveLayout)

    document.documentElement.style.setProperty("--live-stage-h", `${liveStageH}px`)
    document.documentElement.style.setProperty("--viewer-stage-h", `${viewerStageH}px`)
    document.documentElement.style.setProperty("--app-header-h", `${safeHeaderH}px`)
    document.documentElement.style.setProperty("--app-footer-h", `${safeFooterH}px`)
    document.documentElement.style.setProperty("--soft-keyboard-inset-h", `${keyboardInsetH}px`)
  }

  _lockPageScrollTop() {
    window.scrollTo(0, 0)
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
