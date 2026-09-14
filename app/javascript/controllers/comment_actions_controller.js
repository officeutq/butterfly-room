import { Controller } from "@hotwired/stimulus"
import * as bootstrap from "bootstrap"

export default class extends Controller {
  static targets = ["toggle", "content"]
  static values = { publisherControl: Boolean, publisherId: String }

  connect() {
    this.popover = null
    this.handleDocumentClick = this.closeOnOutsideClick.bind(this)
    this.handleBeforeCache = this.dispose.bind(this)
    this.bindPopoverEvents = this.bindPopoverEvents.bind(this)

    document.addEventListener("click", this.handleDocumentClick)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    this.dispose()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.popover) {
      this.dispose()
      return
    }

    this.closeOtherPopovers()

    this.popover = new bootstrap.Popover(this.toggleTarget, {
      trigger: "manual",
      placement: "auto",
      html: true,
      sanitize: false,
      container: "body",
      fallbackPlacements: ["top", "bottom", "right", "left"],
      customClass: "comment-actions-popover",
      content: this.popoverContent()
    })

    this.toggleTarget.addEventListener("shown.bs.popover", this.bindPopoverEvents, { once: true })
    this.popover.show()
  }

  popoverContent() {
    if (!this.publisherControlValue) return this.contentTarget.innerHTML

    // 同じ配信HTMLを受け取っても、本人専用の操作はその人のブラウザーだけに出す。
    const content = document.createElement("div")
    content.innerHTML = this.contentTarget.innerHTML
    const viewerId = document.body.dataset.currentUserId
    if (!viewerId || !this.publisherIdValue || viewerId !== this.publisherIdValue) {
      content.querySelectorAll("[data-comment-moderator-action]").forEach((action) => action.remove())
    }
    return content.innerHTML
  }

  bindPopoverEvents() {
    const popoverId = this.toggleTarget.getAttribute("aria-describedby")
    if (!popoverId) return

    const popoverElement = document.getElementById(popoverId)
    if (!popoverElement) return

    popoverElement.querySelectorAll("form").forEach((form) => {
      form.addEventListener("submit", () => {
        this.dispose()
      }, { once: true })
    })
  }

  closeOnOutsideClick(event) {
    if (!this.popover) return
    if (this.element.contains(event.target)) return

    const popoverId = this.toggleTarget.getAttribute("aria-describedby")
    const popoverElement = popoverId ? document.getElementById(popoverId) : null

    if (popoverElement?.contains(event.target)) return

    this.dispose()
  }

  closeOtherPopovers() {
    document.dispatchEvent(
      new CustomEvent("comment-actions:close", {
        detail: { except: this }
      })
    )

    document.addEventListener(
      "comment-actions:close",
      (event) => {
        if (event.detail?.except === this) return
        this.dispose()
      },
      { once: true }
    )
  }

  dispose() {
    if (!this.popover) return

    this.popover.dispose()
    this.popover = null
  }
}
