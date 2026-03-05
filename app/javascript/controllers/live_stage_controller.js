import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // live中だけスクロールを殺す（non-live へ影響を残さない）
    this._prevHtmlOverflow = document.documentElement.style.overflow
    this._prevBodyOverflow = document.body.style.overflow
    document.documentElement.style.overflow = "hidden"
    document.body.style.overflow = "hidden"

    this._update = this._update.bind(this)

    // window events
    window.addEventListener("resize", this._update)
    window.addEventListener("orientationchange", this._update)

    // visualViewport events（iOS Safari 対策）
    this._vv = window.visualViewport || null
    if (this._vv) {
      this._vv.addEventListener("resize", this._update)
      // アドレスバー出入り等で height 変化が scroll で発生するケースがある
      this._vv.addEventListener("scroll", this._update)
    }

    // 初回計測（layout描画後に安定させる）
    requestAnimationFrame(() => this._update())
  }

  disconnect() {
    window.removeEventListener("resize", this._update)
    window.removeEventListener("orientationchange", this._update)

    if (this._vv) {
      this._vv.removeEventListener("resize", this._update)
      this._vv.removeEventListener("scroll", this._update)
    }

    // スクロール抑止を戻す（liveだけの副作用に閉じる）
    document.documentElement.style.overflow = this._prevHtmlOverflow
    document.body.style.overflow = this._prevBodyOverflow
  }

  _update() {
    const header = document.getElementById("app_header")
    const footer = document.getElementById("app_footer")

    const headerH = header ? header.getBoundingClientRect().height : 0
    const footerH = footer ? footer.getBoundingClientRect().height : 0

    const viewportH = this._vv?.height || window.innerHeight || 0

    // 端末・バー出入りのタイミングで小数や負数が出るので丸め＆下限
    const stageH = Math.max(0, Math.round(viewportH - headerH - footerH))

    document.documentElement.style.setProperty("--live-stage-h", `${stageH}px`)
  }
}
