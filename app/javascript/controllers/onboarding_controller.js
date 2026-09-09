import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  static values = {
    step: String,
    storeId: Number,
    skipUrl: String,
    inviteCastImageUrl: String,
    createInviteImageUrl: String,
    goDashboardImageUrl: String,
    setupDrinksImageUrl: String
  }

  connect() {
    this.modalOpen = false
    this.highlightedElement = null
    this.popoverTarget = null
    this.popover = null

    this.handleUpdate = this.update.bind(this)
    this.handleBeforeCache = this.beforeCache.bind(this)
    this.handleModalOpening = () => { this.modalOpen = true; this.beforeCache() }
    this.handleModalClosed = () => { this.modalOpen = false; this.render() }

    window.addEventListener("onboarding:update", this.handleUpdate)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
    window.addEventListener("app-modal:opening", this.handleModalOpening)
    window.addEventListener("app-modal:closed", this.handleModalClosed)

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.render()
      })
    })
  }

  disconnect() {
    window.removeEventListener("onboarding:update", this.handleUpdate)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    window.removeEventListener("app-modal:opening", this.handleModalOpening)
    window.removeEventListener("app-modal:closed", this.handleModalClosed)
    window.clearTimeout(this.popoverTimeout)

    this.removeHighlight()
    this.disposePopover()
  }

  beforeCache() {
    window.clearTimeout(this.popoverTimeout)
    this.removeHighlight()
    this.disposePopover()
  }

  update(event) {
    const step = event.detail?.step
    if (!step) return

    this.stepValue = step
    if (event.detail?.storeId) this.storeIdValue = event.detail.storeId
    this.beforeCache()
    this.render()
  }

  render() {
    if (this.modalOpen || document.querySelector(".modal.show")) return
    const config = this.stepConfig()
    if (!config) return

    const target = document.querySelector(
      `[data-onboarding-target-element="${config.target}"]`
    )
    if (!target) return

    this.applyHighlight(target)

    if (this.shouldAutoScroll(config.target)) {
      this.scrollTargetIntoView(target)

      this.popoverTimeout = window.setTimeout(() => {
        if (this.modalOpen || !document.body.contains(target)) return
        this.showPopover(target, config.message, config.imageUrl, config.showSkip !== false)
      }, 400)

      return
    }

    this.showPopover(target, config.message, config.imageUrl, config.showSkip !== false)
  }

  stepConfig() {
    switch (this.stepValue) {
      case "invite_cast":
      case "create_invite":
        return {
          target: "footer-cast-invite",
          message: "まずはキャストを招待しましょう。下の『キャスト招待』を押してください。",
          imageUrl: this.inviteCastImageUrlValue
        }

      case "go_dashboard_for_drinks":
        return {
          target: "footer-dashboard",
          message: "次はドリンク設定です。ダッシュボードを開いてください。",
          imageUrl: this.goDashboardImageUrlValue
        }

      case "setup_drinks":
        if (document.querySelector('[data-onboarding-target-element="create-drink-card"]')) {
          return {
            target: "create-drink-card",
            message: "新しいドリンクを、1件追加してみましょう。",
            imageUrl: this.setupDrinksImageUrlValue
          }
        }

        if (document.querySelector('[data-onboarding-target-element="update-drink-submit"]')) {
          return {
            target: "update-drink-submit",
            message: "新しいドリンクを、1件追加してみましょう。",
            imageUrl: this.setupDrinksImageUrlValue
          }
        }

        return {
          target: "setup-drinks-card",
          message: "ドリンク設定を確認しましょう。いくつかデフォルトのドリンクが登録されています。編集・追加もできます！",
          imageUrl: this.inviteCastImageUrlValue
        }

      default:
        return null
    }
  }

  shouldAutoScroll(targetName) {
    return [
      "footer-cast-invite",
      "setup-drinks-card",
      "create-drink-card",
      "footer-dashboard"
    ].includes(targetName)
  }

  scrollTargetIntoView(target) {
    target.scrollIntoView({
      behavior: "smooth",
      block: "center",
      inline: "nearest"
    })
  }

  applyHighlight(element) {
    this.removeHighlight()
    this.highlightedElement = element
    this.highlightedElement.classList.add("tutorial-highlight")
  }

  removeHighlight() {
    if (!this.highlightedElement) return
    this.highlightedElement.classList.remove("tutorial-highlight")
    this.highlightedElement = null
  }

  showPopover(target, message, imageUrl, showSkip) {
    this.disposePopover()

    this.popoverTarget = target

    this.popover = new bootstrap.Popover(target, {
      trigger: "manual",
      placement: "auto",
      html: true,
      sanitize: false,
      container: "body",
      fallbackPlacements: ["top", "bottom", "right", "left"],
      customClass: "tutorial-popover",
      content: this.popoverContent(message, imageUrl, showSkip)
    })

    target.addEventListener("shown.bs.popover", this.handleShownPopover, { once: true })
    this.popover.show()
  }

  handleShownPopover = () => {
    const popoverId = this.popoverTarget?.getAttribute("aria-describedby")
    if (!popoverId) return

    const popoverElement = document.getElementById(popoverId)
    if (!popoverElement) return

    const skipButton = popoverElement.querySelector(".tutorial-popover-skip")

    skipButton?.addEventListener("click", async () => {
      await this.skip()
    })
  }

  popoverContent(message, imageUrl, showSkip) {
    return `
      <div class="tutorial-popover-inner">
        <div class="tutorial-popover-layout">
          <div class="tutorial-popover-media">
            ${
              imageUrl
                ? `<img src="${imageUrl}" alt="" class="tutorial-popover-image">`
                : `<div class="tutorial-popover-image tutorial-popover-image--placeholder"></div>`
            }
          </div>

          <div class="tutorial-popover-content">
            <div class="tutorial-popover-body-text">${message}</div>
            ${
              showSkip
                ? `
                  <div class="tutorial-popover-actions">
                    <button type="button" class="tutorial-popover-skip">
                      スキップ
                    </button>
                  </div>
                `
                : ""
            }
          </div>
        </div>
      </div>
    `
  }

  disposePopover() {
    if (this.popover) {
      this.popover.dispose()
      this.popover = null
    }
    this.popoverTarget = null
  }

  async skip() {
    if (!this.skipUrlValue) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken) return

    const response = await fetch(this.skipUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json",
        "Accept": "text/plain"
      },
      body: JSON.stringify({ store_id: this.storeIdValue || undefined }),
      credentials: "same-origin"
    })

    if (!response.ok) return
    this.stepValue = "skipped"

    this.removeHighlight()
    this.disposePopover()
  }
}
