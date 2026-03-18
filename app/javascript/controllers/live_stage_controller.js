import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // viewer / live ともにスクロールを殺す
    this._vv = window.visualViewport || null
    this._prevHtmlOverflow = document.documentElement.style.overflow
    this._prevBodyOverflow = document.body.style.overflow
    document.documentElement.style.overflow = "hidden"
    document.body.style.overflow = "hidden"

    this._onFocusIn = this._onFocusIn.bind(this)
    this._onFocusOut = this._onFocusOut.bind(this)
    this._onResize = this._onResize.bind(this)

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

    document.body.classList.remove("keyboard-open", "cast-live-keyboard-open")

    document.documentElement.style.overflow = this._prevHtmlOverflow
    document.body.style.overflow = this._prevBodyOverflow

    document.documentElement.style.removeProperty("--live-stage-h")
    document.documentElement.style.removeProperty("--viewer-stage-h")
    document.documentElement.style.removeProperty("--app-header-h")
    document.documentElement.style.removeProperty("--app-footer-h")
  }

  onCommentSubmitStart(_event) {
    // 試験用: 何もしない
  }

  onCommentSubmitEnd(_event) {
    // 試験用: 何もしない
  }

  _onResize() {
    // 端末回転や通常リサイズ時だけ静的値を取り直す
    // キーボード開閉に追随するための再計算はしない
    this._applyStaticLayoutVars()
  }

  _onFocusIn() {
    if (!this._isMobileLike()) return
    if (!document.body.classList.contains("cast-live-layout")) return
    if (!this._hasTextInputFocus()) return

    document.body.classList.add("keyboard-open", "cast-live-keyboard-open")

    requestAnimationFrame(() => {
      this._trimScrollToVisualViewportOffsetTop()
    })

    window.setTimeout(() => {
      this._trimScrollToVisualViewportOffsetTop()
    }, 100)

    window.setTimeout(() => {
      this._trimScrollToVisualViewportOffsetTop()
    }, 250)
  }

  _onFocusOut() {
    requestAnimationFrame(() => {
      if (this._hasTextInputFocus()) return
      document.body.classList.remove("keyboard-open", "cast-live-keyboard-open")
    })
  }

  _trimScrollToVisualViewportOffsetTop() {
    if (!this._vv) return

    const offsetTop = Math.max(0, Math.round(this._vv.offsetTop || 0))
    const scrollY = Math.max(0, Math.round(window.scrollY || 0))

    if (scrollY > offsetTop) {
      window.scrollTo(0, offsetTop)
    }
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
