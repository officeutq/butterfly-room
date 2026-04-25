import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async share(event) {
    event.preventDefault()

    const title = this.element.dataset.shareTitle || document.title
    const text = this.element.dataset.shareText || ""
    const url = this.element.dataset.shareUrl

    if (!url) return

    if (!navigator.share) {
      this.showFlash("warning", "このブラウザでは共有機能を利用できません。コピーをご利用ください。")
      return
    }

    this.element.disabled = true

    try {
      await navigator.share({ title, text, url })
      const step = await this.notifyOnboardingShareIfNeeded()

      if (step) {
        window.dispatchEvent(new CustomEvent("onboarding:update", { detail: { step } }))
      }
    } catch (error) {
      if (error?.name !== "AbortError") {
        this.showFlash("danger", "共有に失敗しました")
      }
    } finally {
      window.setTimeout(() => {
        this.element.disabled = false
      }, 300)
    }
  }

  async notifyOnboardingShareIfNeeded() {
    const url = this.element.dataset.shareOnboardingShareUrlValue
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

    flashInner.replaceChildren(wrapper.firstElementChild)
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }
}
