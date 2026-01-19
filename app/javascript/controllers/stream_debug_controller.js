import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onBefore = (event) => {
      // turbo-stream-element を受け取る直前
      const el = event.target
      if (el && el.tagName === "TURBO-STREAM") {
        const action = el.getAttribute("action")
        const target = el.getAttribute("target")
        this.element.textContent = `last turbo-stream: action=${action} target=${target} at ${new Date().toLocaleTimeString()}`
      }
    }

    document.addEventListener("turbo:before-stream-render", this.onBefore)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.onBefore)
  }
}
