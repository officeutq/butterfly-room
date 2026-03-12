import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // viewer / live ともにスクロールを殺す
    this._prevHtmlOverflow = document.documentElement.style.overflow
    this._prevBodyOverflow = document.body.style.overflow
    document.documentElement.style.overflow = "hidden"
    document.body.style.overflow = "hidden"

    this._update = this._update.bind(this)

    window.addEventListener("resize", this._update)
    window.addEventListener("orientationchange", this._update)

    this._vv = window.visualViewport || null
    if (this._vv) {
      this._vv.addEventListener("resize", this._update)
      this._vv.addEventListener("scroll", this._update)
    }

    requestAnimationFrame(() => this._update())
  }

  disconnect() {
    window.removeEventListener("resize", this._update)
    window.removeEventListener("orientationchange", this._update)

    if (this._vv) {
      this._vv.removeEventListener("resize", this._update)
      this._vv.removeEventListener("scroll", this._update)
    }

    document.documentElement.style.overflow = this._prevHtmlOverflow
    document.body.style.overflow = this._prevBodyOverflow
  }

  _update() {
    const header = document.getElementById("app_header")
    const footer = document.getElementById("app_footer")

    const headerH = header ? header.getBoundingClientRect().height : 0
    const footerH = footer ? footer.getBoundingClientRect().height : 0
    const viewportH = this._vv?.height || window.innerHeight || 0

    const safeViewportH = Math.max(0, Math.round(viewportH))
    const safeHeaderH = Math.max(0, Math.round(headerH))
    const safeFooterH = Math.max(0, Math.round(footerH))

    // cast/live は従来どおり viewport 全体基準
    const liveStageH = safeViewportH

    // viewer は header / footer を除いた本文可視領域
    const viewerStageH = Math.max(0, safeViewportH - safeHeaderH - safeFooterH)

    document.documentElement.style.setProperty("--live-stage-h", `${liveStageH}px`)
    document.documentElement.style.setProperty("--viewer-stage-h", `${viewerStageH}px`)
    document.documentElement.style.setProperty("--app-header-h", `${safeHeaderH}px`)
    document.documentElement.style.setProperty("--app-footer-h", `${safeFooterH}px`)
  }
}
