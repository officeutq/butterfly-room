import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["header", "reveal"]

  connect() {
    this.onScroll = this.updateHeader.bind(this)
    this.element.classList.add("store-lp-202609--enhanced")
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.updateHeader()
    this.observeRevealTargets()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.revealObserver?.disconnect()
    this.revealObserver = null
  }

  updateHeader() {
    if (!this.hasHeaderTarget) return

    this.headerTarget.classList.toggle("is-scrolled", window.scrollY > 24)
  }

  observeRevealTargets() {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (reducedMotion || typeof window.IntersectionObserver !== "function") {
      this.revealTargets.forEach((target) => target.classList.add("is-visible"))
      return
    }

    this.revealObserver = new window.IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return

          entry.target.classList.add("is-visible")
          this.revealObserver?.unobserve(entry.target)
        })
      },
      { rootMargin: "0px 0px -8%", threshold: 0.08 }
    )

    this.revealTargets.forEach((target) => this.revealObserver.observe(target))
  }
}
