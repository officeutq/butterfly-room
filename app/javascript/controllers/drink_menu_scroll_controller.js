import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "butterfly-room:admin-drink-items:scroll-y"

export default class extends Controller {
  connect() {
    this.restore()
  }

  store() {
    try {
      sessionStorage.setItem(STORAGE_KEY, window.scrollY.toString())
    } catch (_) {
      // Ignore storage failures; scroll restoration is a small convenience.
    }
  }

  restore() {
    const storedScrollY = this.consumeStoredScrollY()
    if (storedScrollY === null) return

    const scrollY = Number.parseInt(storedScrollY, 10)
    if (!Number.isFinite(scrollY)) return

    this.restoreTo(scrollY)
    requestAnimationFrame(() => this.restoreTo(scrollY))
    window.setTimeout(() => this.restoreTo(scrollY), 100)
  }

  restoreTo(scrollY) {
    window.scrollTo({ top: scrollY, left: 0, behavior: "auto" })
  }

  consumeStoredScrollY() {
    try {
      const storedScrollY = sessionStorage.getItem(STORAGE_KEY)
      sessionStorage.removeItem(STORAGE_KEY)
      return storedScrollY
    } catch (_) {
      return null
    }
  }
}
