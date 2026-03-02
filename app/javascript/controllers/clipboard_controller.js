import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async copy(event) {
    event.preventDefault()

    const text = this.element.dataset.clipboardText
    if (!text) return

    const original = this.element.textContent
    this.element.disabled = true

    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text)
      } else {
        // Fallback: older browsers / insecure context
        const ta = document.createElement("textarea")
        ta.value = text
        ta.setAttribute("readonly", "")
        ta.style.position = "absolute"
        ta.style.left = "-9999px"
        document.body.appendChild(ta)
        ta.select()
        document.execCommand("copy")
        document.body.removeChild(ta)
      }

      this.element.textContent = "コピーしました"
    } catch (_e) {
      this.element.textContent = "コピー失敗"
    } finally {
      window.setTimeout(() => {
        this.element.textContent = original
        this.element.disabled = false
      }, 1500)
    }
  }
}
