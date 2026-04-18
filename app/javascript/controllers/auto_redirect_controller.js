import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    delay: { type: Number, default: 1000 }
  }

  connect() {
    if (!this.hasUrlValue) return

    this.timer = setTimeout(() => {
      window.location.href = this.urlValue
    }, this.delayValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }
}
