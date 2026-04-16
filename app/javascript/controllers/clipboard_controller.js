import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async copy(event) {
    event.preventDefault()

    const text = this.element.dataset.clipboardText
    if (!text) return

    const successMessage = this.element.dataset.clipboardSuccessMessage || "コピーしました"
    const failureMessage = this.element.dataset.clipboardFailureMessage || "コピー失敗"

    this.element.disabled = true

    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text)
      } else {
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

      const step = await this.notifyOnboardingCopyIfNeeded()

      this.showFlash("success", successMessage)

      if (step) {
        window.dispatchEvent(new CustomEvent("onboarding:update", { detail: { step } }))
      }
    } catch (_e) {
      this.showFlash("danger", failureMessage)
    } finally {
      window.setTimeout(() => {
        this.element.disabled = false
      }, 300)
    }
  }

  async notifyOnboardingCopyIfNeeded() {
    const url = this.element.dataset.clipboardOnboardingCopyUrlValue
    if (!url) return null

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) return null

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      credentials: "same-origin"
    })

    if (!response.ok) return null

    const json = await response.json()
    return json.step
  }

  showFlash(level, message) {
    const flashInner = document.getElementById("flash_inner")
    if (!flashInner) return

    const wrapper = document.createElement("div")
    wrapper.innerHTML = `
      <div class="alert alert-${level} alert-dismissible fade show" role="alert">
        ${this.escapeHtml(message)}
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="閉じる"></button>
      </div>
    `.trim()

    const flashElement = wrapper.firstElementChild
    flashInner.replaceChildren(flashElement)
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }
}
