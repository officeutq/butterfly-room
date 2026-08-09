import { Controller } from "@hotwired/stimulus"
import {
  EventSender,
  isTrackableDocument,
  rememberVisitId,
  viewportType,
} from "lp_analytics/event_sender"

const SCROLL_THRESHOLDS = [25, 50, 75, 90]
const TRACKED_ONCE_STORAGE_PREFIX = "lp_analytics_tracked_once:"

export default class extends Controller {
  static values = {
    eventsUrl: String,
    visitId: String,
  }

  connect() {
    this.onScroll = this.handleScroll.bind(this)
    this.onQuestionClick = this.toggleQuestion.bind(this)
    this.onAnchorClick = this.scrollToAnchor.bind(this)
    this.onAnswerTransitionEnd = this.finishOpeningAnswer.bind(this)
    this.onCtaClick = this.trackCtaClick.bind(this)
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
    this.startAnalytics()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.stopAnalytics()
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
      this.sendAnalytics("faq_opened", item.dataset.lpAnalyticsFaqValue)
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

  handleScroll() {
    this.fadeInVisibleElements()
    this.scheduleScrollTracking()
  }

  startAnalytics() {
    this.analyticsEnabled = false
    this.trackedOnceEvents = new Set()
    if (
      !this.hasEventsUrlValue ||
      !this.hasVisitIdValue ||
      !this.visitIdValue ||
      !isTrackableDocument()
    ) return

    rememberVisitId(this.visitIdValue)
    this.eventSender = new EventSender({
      eventsUrl: this.eventsUrlValue,
      visitId: this.visitIdValue,
    })
    this.trackedOnceEvents = this.loadTrackedOnceEvents()
    this.analyticsEnabled = true
    this.ctaLinks.forEach((link) => link.addEventListener("click", this.onCtaClick))
    this.sendAnalytics("lp_view")
    this.trackScrollReached()
    this.startReachObserver()
  }

  stopAnalytics() {
    this.ctaLinks.forEach((link) => link.removeEventListener("click", this.onCtaClick))
    this.reachObserver?.disconnect()
    this.reachObserver = null
    if (this.scrollTrackingFrame) window.cancelAnimationFrame(this.scrollTrackingFrame)
    this.scrollTrackingFrame = null
    this.analyticsEnabled = false
  }

  startReachObserver() {
    if (typeof window.IntersectionObserver !== "function") {
      this.trackVisibleReachTargets()
      return
    }

    this.reachObserver = new window.IntersectionObserver(
      (entries) => this.handleReachEntries(entries),
      { threshold: 0.01 }
    )
    this.reachTargets.forEach((target) => this.reachObserver.observe(target))
  }

  handleReachEntries(entries) {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return

      this.trackReachTarget(entry.target)
      this.reachObserver?.unobserve(entry.target)
    })
  }

  trackVisibleReachTargets() {
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    this.reachTargets.forEach((target) => {
      const rect = target.getBoundingClientRect()
      if (rect.bottom <= 0 || rect.top >= viewportHeight) return

      this.trackReachTarget(target)
    })
  }

  trackReachTarget(target) {
    const eventType = target.dataset.lpAnalyticsReachType
    const eventValue = target.dataset.lpAnalyticsEventValue
    if (!eventType || !eventValue) return

    const dedupeKey = `${eventType}:${eventValue}`
    this.sendOnceAnalytics(dedupeKey, eventType, eventValue)
  }

  scheduleScrollTracking() {
    if (!this.analyticsEnabled || this.scrollTrackingFrame) return

    this.scrollTrackingFrame = window.requestAnimationFrame(() => {
      this.scrollTrackingFrame = null
      this.trackScrollReached()
      if (!this.reachObserver) this.trackVisibleReachTargets()
    })
  }

  trackScrollReached() {
    if (!this.analyticsEnabled) return

    const documentElement = document.documentElement
    const body = document.body
    const viewportHeight = window.innerHeight || documentElement.clientHeight
    const scrollTop = window.scrollY || documentElement.scrollTop || body.scrollTop || 0
    const scrollHeight = Math.max(documentElement.scrollHeight, body.scrollHeight)
    const reachedPercent = scrollHeight > 0
      ? ((scrollTop + viewportHeight) / scrollHeight) * 100
      : 100

    SCROLL_THRESHOLDS.forEach((threshold) => {
      if (reachedPercent < threshold) return

      const eventValue = String(threshold)
      this.sendOnceAnalytics(`scroll_reached:${eventValue}`, "scroll_reached", eventValue)
    })
  }

  sendOnceAnalytics(dedupeKey, eventType, eventValue) {
    if (this.trackedOnceEvents.has(dedupeKey)) return

    this.trackedOnceEvents.add(dedupeKey)
    this.persistTrackedOnceEvents()
    Promise.resolve(this.sendAnalytics(eventType, eventValue)).then((succeeded) => {
      if (succeeded) return

      this.trackedOnceEvents.delete(dedupeKey)
      this.persistTrackedOnceEvents()
    })
  }

  loadTrackedOnceEvents() {
    try {
      const stored = window.sessionStorage.getItem(this.trackedOnceStorageKey)
      const eventKeys = stored ? JSON.parse(stored) : []
      if (!Array.isArray(eventKeys)) return new Set()

      return new Set(eventKeys.filter((eventKey) => typeof eventKey === "string"))
    } catch (_error) {
      return new Set()
    }
  }

  persistTrackedOnceEvents() {
    try {
      window.sessionStorage.setItem(
        this.trackedOnceStorageKey,
        JSON.stringify(Array.from(this.trackedOnceEvents))
      )
    } catch (_error) {
      // Storage is supplemental; the database remains the final dedupe boundary.
    }
  }

  get trackedOnceStorageKey() {
    return `${TRACKED_ONCE_STORAGE_PREFIX}${this.visitIdValue}`
  }

  trackCtaClick(event) {
    this.sendAnalytics("cta_clicked", event.currentTarget.dataset.lpAnalyticsClickValue)
  }

  sendAnalytics(eventType, eventValue = null) {
    if (!this.analyticsEnabled || !eventType) return Promise.resolve(false)

    return this.eventSender.send(eventType, eventValue, { viewport_type: viewportType() })
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

  get reachTargets() {
    return Array.from(this.element.querySelectorAll("[data-lp-analytics-reach-type]"))
  }

  get ctaLinks() {
    return Array.from(this.element.querySelectorAll("[data-lp-analytics-click-value]"))
  }
}
