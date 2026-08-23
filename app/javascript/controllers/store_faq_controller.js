import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["category", "categoryLink"]

  connect() {
    const category = this.categoryForHash(window.location.hash) || this.categoryTargets[0]
    this.selectCategory(category?.dataset.categoryKey)
  }

  scrollToCategory(event) {
    const category = document.getElementById(event.currentTarget.getAttribute("aria-controls"))
    if (!category) return

    event.preventDefault()
    this.selectCategory(category.dataset.categoryKey)
    category.scrollIntoView({ behavior: this.scrollBehavior(), block: "start" })
  }

  scrollToTop(event) {
    event.preventDefault()
    this.selectCategory(this.categoryTargets[0]?.dataset.categoryKey)
    window.scrollTo({ top: 0, behavior: this.scrollBehavior() })
  }

  toggleQuestion(event) {
    event.preventDefault()

    const details = event.currentTarget.closest("details")
    if (!details) return

    details._storeFaqAnimation?.cancel()

    if (this.reducedMotion() || typeof details.animate !== "function") {
      details.open = !details.open
      return
    }

    this.animateQuestion(details, !details.open)
  }

  animateQuestion(details, opening) {
    const summary = details.querySelector("summary")
    const startHeight = details.offsetHeight

    if (opening) details.open = true

    const endHeight = opening ? details.offsetHeight : summary.offsetHeight
    details.style.height = `${startHeight}px`
    details.style.overflow = "hidden"
    details.dataset.animating = "true"

    const animation = details.animate(
      { height: [`${startHeight}px`, `${endHeight}px`] },
      { duration: 260, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
    )

    details._storeFaqAnimation = animation
    animation.onfinish = () => this.finishQuestionAnimation(details, opening)
    animation.oncancel = () => this.clearQuestionAnimationStyles(details)
  }

  finishQuestionAnimation(details, opening) {
    details.open = opening
    this.clearQuestionAnimationStyles(details)
  }

  clearQuestionAnimationStyles(details) {
    details.style.removeProperty("height")
    details.style.removeProperty("overflow")
    delete details.dataset.animating
    details._storeFaqAnimation = null
  }

  selectCategory(categoryKey) {
    if (!categoryKey) return

    this.categoryLinkTargets.forEach((link) => {
      const selected = link.dataset.categoryKey === categoryKey
      link.classList.toggle("is-active", selected)
      if (selected) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }

  categoryForHash(hash) {
    if (!/^#(?:store-faq-category-[a-z0-9-]+|faq-q\d+)$/.test(hash)) return null

    return this.categoryTargets.find((category) => {
      return `#${category.id}` === hash || category.querySelector(hash)
    })
  }

  scrollBehavior() {
    return this.reducedMotion() ? "auto" : "smooth"
  }

  reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
