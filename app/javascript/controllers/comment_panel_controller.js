import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list"]

  connect() {
    this._thresholdPx = 24
    this._nearBottom = true

    this._onScroll = () => {
      this._nearBottom = this._isNearBottom()
    }

    this.listTarget.addEventListener("scroll", this._onScroll)

    // 初期表示：最新に寄せる（コメント0でもOK）
    this._scrollToBottom()

    this._observer = new MutationObserver(() => {
      // 直前の状態（ユーザーが下付近にいるか）に基づいて追従
      if (this._nearBottom) this._scrollToBottom()
    })

    this._observer.observe(this.listTarget, { childList: true })
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }

    if (this._onScroll) {
      this.listTarget.removeEventListener("scroll", this._onScroll)
      this._onScroll = null
    }
  }

  _isNearBottom() {
    const el = this.listTarget
    const distance = el.scrollHeight - (el.scrollTop + el.clientHeight)
    return distance < this._thresholdPx
  }

  _scrollToBottom() {
    const el = this.listTarget
    el.scrollTop = el.scrollHeight
  }
}
