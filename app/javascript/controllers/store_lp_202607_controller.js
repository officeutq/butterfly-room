import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onScroll = this.fadeInVisibleElements.bind(this)
    this.onQuestionClick = this.toggleQuestion.bind(this)
    this.onAnchorClick = this.scrollToAnchor.bind(this)
    this.onAnswerTransitionEnd = this.finishOpeningAnswer.bind(this)
    this.questionItems.forEach((item) => {
      const answer = item.querySelector(".a")
      const question = item.querySelector(".q")
      if (answer) this.collapseAnswer(answer, false)
      question?.setAttribute("aria-expanded", "false")
      item.addEventListener("click", this.onQuestionClick)
    })
    this.anchorLinks.forEach((link) => {
      link.addEventListener("click", this.onAnchorClick)
    })
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.fadeInVisibleElements()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.questionItems.forEach((item) => {
      item.removeEventListener("click", this.onQuestionClick)
      item.querySelector(".a")?.removeEventListener("transitionend", this.onAnswerTransitionEnd)
    })
    this.anchorLinks.forEach((link) => {
      link.removeEventListener("click", this.onAnchorClick)
    })
  }

  toggleQuestion(event) {
    const item = event.currentTarget
    const answer = item.querySelector(".a")
    const question = item.querySelector(".q")
    if (!answer || !question) return

    const shouldOpen = answer.dataset.open !== "true"
    this.questionItems.forEach((otherItem) => {
      if (otherItem === item) return

      const otherAnswer = otherItem.querySelector(".a")
      const otherQuestion = otherItem.querySelector(".q")
      if (otherAnswer) this.collapseAnswer(otherAnswer)
      otherQuestion?.classList.remove("active")
      otherQuestion?.setAttribute("aria-expanded", "false")
    })

    if (shouldOpen) {
      this.expandAnswer(answer)
      question.classList.add("active")
      question.setAttribute("aria-expanded", "true")
    } else {
      this.collapseAnswer(answer)
      question.classList.remove("active")
      question.setAttribute("aria-expanded", "false")
    }
  }

  expandAnswer(answer) {
    answer.dataset.open = "true"
    answer.classList.add("is-open")
    answer.style.height = `${answer.scrollHeight}px`
    answer.addEventListener("transitionend", this.onAnswerTransitionEnd)
  }

  collapseAnswer(answer, animate = true) {
    answer.dataset.open = "false"
    answer.classList.remove("is-open")
    answer.removeEventListener("transitionend", this.onAnswerTransitionEnd)

    if (animate) {
      answer.style.height = `${answer.scrollHeight}px`
      void answer.offsetHeight
    }

    answer.style.height = "0px"
  }

  finishOpeningAnswer(event) {
    if (event.propertyName !== "height") return
    if (event.currentTarget.dataset.open !== "true") return

    event.currentTarget.style.height = "auto"
    event.currentTarget.removeEventListener("transitionend", this.onAnswerTransitionEnd)
  }

  scrollToAnchor(event) {
    const href = event.currentTarget.getAttribute("href")
    if (!href || !href.startsWith("#")) return

    event.preventDefault()
    const target = href === "#" ? null : document.getElementById(href.slice(1))
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"

    if (target) {
      target.scrollIntoView({ behavior, block: "start" })
    } else {
      window.scrollTo({ top: 0, behavior })
    }

    this.fadeInVisibleElements()
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

  get anchorLinks() {
    return Array.from(this.element.querySelectorAll('a[href^="#"]'))
  }

  get fadeTargets() {
    return Array.from(this.element.querySelectorAll(".fadeUpTrigger, [class*='fadeUp_trig_']"))
  }
}
