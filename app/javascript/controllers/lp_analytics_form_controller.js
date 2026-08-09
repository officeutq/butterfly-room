import { Controller } from "@hotwired/stimulus"
import {
  EventSender,
  isTrackableDocument,
  storedVisitId,
  viewportType,
} from "lp_analytics/event_sender"

export default class extends Controller {
  static values = {
    eventsUrl: String,
    eventType: String,
  }

  connect() {
    if (!this.hasEventsUrlValue || !this.hasEventTypeValue || !isTrackableDocument()) return

    const visitId = storedVisitId()
    this.setVisitIdInput(visitId)
    this.eventSender = new EventSender({ eventsUrl: this.eventsUrlValue, visitId })
    this.eventSender.send(this.eventTypeValue, null, { viewport_type: viewportType() })
  }

  setVisitIdInput(visitId) {
    if (!visitId || this.element.tagName !== "FORM") return

    let input = this.element.querySelector('input[name="lp_analytics_visit_id"]')
    if (!input) {
      input = document.createElement("input")
      input.type = "hidden"
      input.name = "lp_analytics_visit_id"
      this.element.appendChild(input)
    }
    input.value = visitId
  }
}
