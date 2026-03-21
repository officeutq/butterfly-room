import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list"]

  connect() {
    this._thresholdPx = 24
    this._nearBottom = true
    this._rafId = null

    this._onScroll = () => {
      this._nearBottom = this._isNearBottom()
    }

    this.listTarget.addEventListener("scroll", this._onScroll)

    // 初期表示：レイアウト確定後に最下部へ
    this._scheduleScrollToBottom()

    this._observer = new MutationObserver(() => {
      if (!this._nearBottom) return
      this._scheduleScrollToBottom()
    })

    this._observer.observe(this.listTarget, { childList: true })
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }

    if (this._rafId) {
      cancelAnimationFrame(this._rafId)
      this._rafId = null
    }

    if (this._onScroll) {
      this.listTarget.removeEventListener("scroll", this._onScroll)
      this._onScroll = null
    }
  }

  scrollToBottomNow() {
    this._scheduleScrollToBottom()
  }

  _isNearBottom() {
    const el = this.listTarget
    const distance = el.scrollHeight - (el.scrollTop + el.clientHeight)
    return distance < this._thresholdPx
  }

  _scheduleScrollToBottom() {
    if (this._rafId) cancelAnimationFrame(this._rafId)

    this._rafId = requestAnimationFrame(() => {
      this._scrollToBottom()

      // 1フレーム後にさらに高さが変わるケースに備えてもう1回
      this._rafId = requestAnimationFrame(() => {
        this._scrollToBottom()
        this._nearBottom = true
        this._rafId = null
      })
    })
  }

  _scrollToBottom() {
    const el = this.listTarget
    el.scrollTop = el.scrollHeight
  }
}
