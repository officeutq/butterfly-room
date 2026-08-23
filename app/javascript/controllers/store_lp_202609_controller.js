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
  static targets = ["header", "reveal"]
  static values = {
    eventsUrl: String,
    visitId: String,
  }

  connect() {
    this.onScroll = this.handleScroll.bind(this)
    this.onCtaClick = this.trackCtaClick.bind(this)
    this.element.classList.add("store-lp-202609--enhanced")
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.updateHeader()
    this.observeRevealTargets()
    this.startAnalytics()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.revealObserver?.disconnect()
    this.revealObserver = null
    this.stopAnalytics()
  }

  handleScroll() {
    this.updateHeader()
    this.scheduleScrollTracking()
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

    this.sendOnceAnalytics(`${eventType}:${eventValue}`, eventType, eventValue)
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

  get reachTargets() {
    return Array.from(this.element.querySelectorAll("[data-lp-analytics-reach-type]"))
  }

  get ctaLinks() {
    return Array.from(this.element.querySelectorAll("[data-lp-analytics-click-value]"))
  }
}
