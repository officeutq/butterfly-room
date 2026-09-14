import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["operation", "display"]
  static values = { publisherId: String }

  connect() {
    this.reset()
    const viewerId = document.body.dataset.currentUserId
    if (!viewerId || !this.publisherIdValue || viewerId !== this.publisherIdValue) return

    this.operationTarget.hidden = false
    this.displayTarget.hidden = true
  }

  disconnect() {
    this.reset()
  }

  reset() {
    this.operationTarget.hidden = true
    this.displayTarget.hidden = false
  }
}
