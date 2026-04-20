import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    key: String,
    active: Boolean,
    activeClass: { type: String, default: "is-active" },
    activeIcon: { type: String, default: "bi-star-fill" },
    inactiveIcon: { type: String, default: "bi-star" },
    activeTitle: { type: String, default: "お気に入り解除" },
    inactiveTitle: { type: String, default: "お気に入り" },
    activeAriaLabel: { type: String, default: "お気に入りを解除" },
    inactiveAriaLabel: { type: String, default: "お気に入り" }
  }

  connect() {
    this.syncGroup()
  }

  activeValueChanged() {
    this.syncGroup()
  }

  syncGroup() {
    if (!this.hasKeyValue || !this.keyValue) return

    const selector = `[data-controller~="favorite-sync"][data-favorite-sync-key-value="${CSS.escape(this.keyValue)}"]`
    const elements = document.querySelectorAll(selector)

    elements.forEach((element) => {
      const controller = this.application.getControllerForElementAndIdentifier(element, "favorite-sync")
      if (controller) controller.applyState(this.activeValue)
    })
  }

  applyState(active) {
    this.element.classList.toggle(this.activeClassValue, active)

    const icon = this.element.querySelector("i.bi")
    if (icon) {
      icon.classList.toggle(this.activeIconValue, active)
      icon.classList.toggle(this.inactiveIconValue, !active)
    }

    this.element.title = active ? this.activeTitleValue : this.inactiveTitleValue
    this.element.setAttribute(
      "aria-label",
      active ? this.activeAriaLabelValue : this.inactiveAriaLabelValue
    )
  }
}
