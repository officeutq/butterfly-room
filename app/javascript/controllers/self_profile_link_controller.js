import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { userId: String, url: String }

  connect() {
    this.reset()
    const viewerId = document.body.dataset.currentUserId
    if (!viewerId || viewerId !== this.userIdValue) return

    const link = document.createElement("a")
    link.href = this.urlValue
    link.className = "text-decoration-none text-reset"
    link.textContent = this.element.textContent
    this.element.replaceChildren(link)
  }

  disconnect() {
    this.reset()
  }

  reset() {
    this.element.textContent = this.element.textContent
  }
}
