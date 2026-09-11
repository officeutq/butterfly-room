import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { message: String }

  confirm(event) {
    if (event.defaultPrevented || !this.messageValue) return
    if (window.confirm(this.messageValue)) return

    event.preventDefault()
    event.stopImmediatePropagation()
  }
}
