import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  static values = {
    step: String,
    skipUrl: String,
    inviteCastImageUrl: String,
    createInviteImageUrl: String,
    goDashboardImageUrl: String,
    setupDrinksImageUrl: String
  }

  connect() {
    this.highlightedElement = null
    this.popoverTarget = null
    this.popover = null

    this.handleUpdate = this.update.bind(this)
    this.handleBeforeCache = this.beforeCache.bind(this)

    window.addEventListener("onboarding:update", this.handleUpdate)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.render()
      })
    })
  }

  disconnect() {
    window.removeEventListener("onboarding:update", this.handleUpdate)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)

    this.removeHighlight()
    this.disposePopover()
  }

  beforeCache() {
    this.removeHighlight()
    this.disposePopover()
  }

  update(event) {
    const step = event.detail?.step
    if (!step) return

    this.stepValue = step
    this.removeHighlight()
    this.disposePopover()
    this.render()
  }

  render() {
    const config = this.stepConfig()
    if (!config) return

    const target = document.querySelector(
      `[data-onboarding-target-element="${config.target}"]`
    )
    if (!target) return

    this.applyHighlight(target)

    if (this.shouldAutoScroll(config.target)) {
      this.scrollTargetIntoView(target)

      window.setTimeout(() => {
        if (!document.body.contains(target)) return
        this.showPopover(target, config.message, config.imageUrl, config.showSkip !== false)
      }, 400)

      return
    }

    this.showPopover(target, config.message, config.imageUrl, config.showSkip !== false)
  }

  stepConfig() {
    switch (this.stepValue) {
      case "invite_cast":
        return {
          target: "invite-cast-card",
          message: "店舗に所属する「キャスト」を招待しましょう。このボタンを押してください。",
          imageUrl: this.inviteCastImageUrlValue
        }
      case "create_invite":
        if (document.querySelector('[data-onboarding-target-element="copy-invite-button"]')) {
          return {
            target: "copy-invite-button",
            message: "このボタンで 招待URL を共有できます。",
            imageUrl: this.createInviteImageUrlValue
          }
        }

        if (document.querySelector('[data-onboarding-target-element="issue-invite-button"]')) {
          return {
            target: "issue-invite-button",
            message: "招待URLを発行しましょう。",
            imageUrl: this.createInviteImageUrlValue
          }
        }

        return {
          target: "invite-note-field",
          message: "招待を区別しやすいようにメモを入力できます（任意）。",
          imageUrl: this.createInviteImageUrlValue
        }

      case "go_dashboard_for_drinks":
        return {
          target: "footer-dashboard",
          message: "招待する「キャスト」に共有したら、次はダッシュボードに戻って、ドリンク設定を確認しましょう。",
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
    return ["invite-cast-card", "setup-drinks-card", "create-drink-card"].includes(targetName)
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

    await fetch(this.skipUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/plain"
      },
      credentials: "same-origin"
    })

    this.removeHighlight()
    this.disposePopover()
  }
}
