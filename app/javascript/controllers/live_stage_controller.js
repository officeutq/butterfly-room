import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._vv = window.visualViewport || null

    this._onFocusIn = this._onFocusIn.bind(this)
    this._onFocusOut = this._onFocusOut.bind(this)
    this._onResize = this._onResize.bind(this)

    this._keyboardCloseTimers = []

    this._applyStaticLayoutVars()

    document.addEventListener("focusin", this._onFocusIn)
    document.addEventListener("focusout", this._onFocusOut)
    window.addEventListener("orientationchange", this._onResize)
    window.addEventListener("resize", this._onResize)
  }

  disconnect() {
    document.removeEventListener("focusin", this._onFocusIn)
    document.removeEventListener("focusout", this._onFocusOut)
    window.removeEventListener("orientationchange", this._onResize)
    window.removeEventListener("resize", this._onResize)

    this._clearKeyboardCloseTimers()

    document.body.classList.remove(
      "keyboard-open",
      "cast-live-keyboard-open",
      "viewer-keyboard-open"
    )

    document.documentElement.style.removeProperty("--live-stage-h")
    document.documentElement.style.removeProperty("--viewer-stage-h")
    document.documentElement.style.removeProperty("--app-header-h")
    document.documentElement.style.removeProperty("--app-footer-h")
  }

  _onResize() {
    // 端末回転や通常リサイズ時だけ静的値を取り直す
    // キーボード開閉に追随する再計算はしない
    this._applyStaticLayoutVars()
  }

  _onFocusIn() {
    if (!this._isMobileLike()) return
    if (!this._hasTextInputFocus()) return

    this._clearKeyboardCloseTimers()

    if (this._isCastLiveLayout()) {
      document.body.classList.add("keyboard-open", "cast-live-keyboard-open")
      return
    }

    if (this._isViewerLayout()) {
      document.body.classList.add("keyboard-open", "viewer-keyboard-open")
    }
  }

  _onFocusOut() {
    requestAnimationFrame(() => {
      if (this._hasTextInputFocus()) return

      const wasCastLiveOpen = document.body.classList.contains("cast-live-keyboard-open")

      document.body.classList.remove(
        "keyboard-open",
        "cast-live-keyboard-open",
        "viewer-keyboard-open"
      )

      if (wasCastLiveOpen) {
        this._restoreRootScrollAfterKeyboardClose()
      }
    })
  }

  _restoreRootScrollAfterKeyboardClose() {
    const run = () => {
      const offsetTop = Math.max(0, Math.round(this._vv?.offsetTop || 0))
      if (offsetTop !== 0) return

      const root = document.scrollingElement || document.documentElement

      if (root.scrollTop > 0) {
        root.scrollTop = 0
      }

      if (document.documentElement.scrollTop > 0) {
        document.documentElement.scrollTop = 0
      }

      if (document.body.scrollTop > 0) {
        document.body.scrollTop = 0
      }

      if ((window.scrollY || 0) > 0) {
        window.scrollTo(0, 0)
      }
    }

    requestAnimationFrame(run)
    this._keyboardCloseTimers.push(window.setTimeout(run, 100))
    this._keyboardCloseTimers.push(window.setTimeout(run, 250))
    this._keyboardCloseTimers.push(window.setTimeout(run, 400))
  }

  _clearKeyboardCloseTimers() {
    this._keyboardCloseTimers.forEach((id) => clearTimeout(id))
    this._keyboardCloseTimers = []
  }

  _applyStaticLayoutVars() {
    const header = document.getElementById("app_header")
    const footer = document.getElementById("app_footer")

    const headerH = header ? header.getBoundingClientRect().height : 0
    const footerH = footer ? footer.getBoundingClientRect().height : 0
    const viewportH = window.innerHeight || document.documentElement.clientHeight || 0

    document.documentElement.style.setProperty("--live-stage-h", `${Math.max(0, Math.round(viewportH))}px`)
    document.documentElement.style.setProperty(
      "--viewer-stage-h",
      `${Math.max(0, Math.round(viewportH - headerH - footerH))}px`
    )
    document.documentElement.style.setProperty("--app-header-h", `${Math.max(0, Math.round(headerH))}px`)
    document.documentElement.style.setProperty("--app-footer-h", `${Math.max(0, Math.round(footerH))}px`)
  }

  _isMobileLike() {
    return window.matchMedia("(pointer: coarse)").matches || window.innerWidth < 992
  }

  _isCastLiveLayout() {
    return document.body.classList.contains("cast-live-layout")
  }

  _isViewerLayout() {
    return document.body.classList.contains("viewer-layout")
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
