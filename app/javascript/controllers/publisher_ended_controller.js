import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, sessionId: Number }

  connect() {
    const element = this.element.closest('[data-controller~="ivs-publisher"]')
    const publisher = element && this.application.getControllerForElementAndIdentifier(element, "ivs-publisher")
    if (!publisher || publisher.streamSessionIdValue !== this.sessionIdValue) return

    // 同じセッションの通知だけを受け、AWSの切断結果にかかわらず送信を停止する。
    publisher._publisherEndRequest = null
    publisher._publisherAttempt?.invalidate()
    publisher._cleanupStage()
    publisher._broadcasting = false
    void publisher._cleanupMediaAndCanvas().catch(() => {})
    if (window.Turbo?.visit) window.Turbo.visit(this.urlValue)
    else window.location.assign(this.urlValue)
  }
}
