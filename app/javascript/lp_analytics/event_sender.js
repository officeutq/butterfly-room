const VISIT_STORAGE_KEY = "lp_analytics_visit_id"

export function isTrackableDocument(documentReference = document) {
  const documentElement = documentReference.documentElement
  if (documentElement?.hasAttribute("data-turbo-preview")) return false
  if (documentReference.prerendering === true) return false
  if (documentReference.visibilityState === "prerender") return false

  return true
}

export function viewportType(windowReference = window, documentReference = document) {
  const width = windowReference.innerWidth || documentReference.documentElement?.clientWidth || 0
  if (width <= 767) return "smartphone"
  if (width <= 1024) return "tablet"

  return "pc"
}

export function rememberVisitId(visitId, storage) {
  if (!visitId) return

  try {
    const targetStorage = storage === undefined ? window.sessionStorage : storage
    targetStorage?.setItem(VISIT_STORAGE_KEY, visitId)
  } catch (_error) {
    // Storage may be unavailable in private browsing; Rails session remains the fallback.
  }
}

export function storedVisitId(storage) {
  try {
    const targetStorage = storage === undefined ? window.sessionStorage : storage
    return targetStorage?.getItem(VISIT_STORAGE_KEY) || null
  } catch (_error) {
    return null
  }
}

export class EventSender {
  constructor({
    eventsUrl,
    visitId = null,
    lpIdentifier = null,
    windowReference = window,
    documentReference = document,
  }) {
    this.eventsUrl = eventsUrl
    this.visitId = visitId
    this.lpIdentifier = lpIdentifier
    this.windowReference = windowReference
    this.documentReference = documentReference
  }

  send(eventType, eventValue = null, metadata = {}) {
    const eventId = this.generateUuid()
    const csrfToken = this.documentReference.querySelector('meta[name="csrf-token"]')?.content
    const fetchFunction = this.windowReference.fetch
    if (!this.eventsUrl || !eventType || !eventId || !csrfToken || typeof fetchFunction !== "function") {
      return Promise.resolve(false)
    }

    const event = {
      event_id: eventId,
      event_type: eventType,
    }
    if (this.visitId) event.visit_id = this.visitId
    if (this.lpIdentifier) event.lp_identifier = this.lpIdentifier
    if (eventValue !== null && eventValue !== undefined) event.event_value = eventValue
    if (Object.keys(metadata).length > 0) event.metadata = metadata

    try {
      return Promise.resolve(fetchFunction.call(this.windowReference, this.eventsUrl, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        credentials: "same-origin",
        keepalive: true,
        body: JSON.stringify({ lp_analytics_event: event }),
      }))
        .then((response) => response.ok)
        .catch(() => false)
    } catch (_error) {
      return Promise.resolve(false)
    }
  }

  generateUuid() {
    const crypto = this.windowReference.crypto
    if (typeof crypto?.randomUUID === "function") return crypto.randomUUID()
    if (typeof crypto?.getRandomValues !== "function") return null

    const bytes = crypto.getRandomValues(new Uint8Array(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"))

    return [
      hex.slice(0, 4).join(""),
      hex.slice(4, 6).join(""),
      hex.slice(6, 8).join(""),
      hex.slice(8, 10).join(""),
      hex.slice(10, 16).join(""),
    ].join("-")
  }
}
