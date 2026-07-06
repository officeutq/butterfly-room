import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onScroll = this.fadeInVisibleElements.bind(this)
    this.onQuestionClick = this.toggleQuestion.bind(this)
    this.questionItems.forEach((item) => {
      item.querySelector(".a")?.setAttribute("hidden", "")
      item.addEventListener("click", this.onQuestionClick)
    })
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.fadeInVisibleElements()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.questionItems.forEach((item) => {
      item.removeEventListener("click", this.onQuestionClick)
    })
  }

  toggleQuestion(event) {
    const item = event.currentTarget
    const answer = item.querySelector(".a")
    const question = item.querySelector(".q")
    if (!answer || !question) return

    const shouldOpen = answer.hasAttribute("hidden")
    this.questionItems.forEach((otherItem) => {
      otherItem.querySelector(".a")?.setAttribute("hidden", "")
      otherItem.querySelector(".q")?.classList.remove("active")
    })

    if (shouldOpen) {
      answer.removeAttribute("hidden")
      question.classList.add("active")
    }
  }

  fadeInVisibleElements() {
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    this.fadeTargets.forEach((element) => {
      if (element.classList.contains("fadeUp")) return

      const triggerPercent = this.numberFromClass(element, /fadeUp_trig_(\d+)/, 80) / 100
      const triggerPosition = viewportHeight * triggerPercent
      const rect = element.getBoundingClientRect()
      if (rect.top > triggerPosition) return

      const delay = this.numberFromClass(element, /fadeUp_late_(\d+)/)
      if (delay !== null) element.style.animationDelay = `${delay}ms`

      const distance = this.numberFromClass(element, /fadeUp_dist_(\d+)/, 200)
      element.style.setProperty("--fadeUp-dist", `${distance}px`)

      const duration = this.numberFromClass(element, /fadeUp_dur_(\d+)/, 2000)
      element.style.setProperty("--fadeUp-dur", `${duration}ms`)
      element.classList.add("fadeUp")
    })
  }

  numberFromClass(element, pattern, fallback = null) {
    const match = element.className.match(pattern)
    return match ? Number.parseInt(match[1], 10) : fallback
  }

  get questionItems() {
    return Array.from(this.element.querySelectorAll(".qa_item"))
  }

  get fadeTargets() {
    return Array.from(this.element.querySelectorAll(".fadeUpTrigger, [class*='fadeUp_trig_']"))
  }
}
