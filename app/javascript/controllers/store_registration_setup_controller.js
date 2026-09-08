import { Controller } from "@hotwired/stimulus"

const FIELD_NAMES = [
  "description", "area", "business_type", "address", "phone_number", "business_hours",
  "website_url", "x_url", "instagram_url", "tiktok_url", "youtube_url"
]
const RESULT_MESSAGES = {
  success: "AIで見つかった情報を入力しました。お店の情報に間違いがないか確認し、必要に応じて修正してください。",
  partial: "AIで見つかった情報を入力しました。お店の情報に間違いがないか確認し、必要に応じて修正してください。",
  not_found: "店舗情報が見つかりませんでした。手入力で続けられます",
  ambiguous: "店舗を特定できませんでした。手入力で続けられます",
  error: "AI入力を利用できませんでした。手入力で続けられます",
  unauthorized: "ログイン状態または店舗の管理権限を確認できませんでした。再ログインまたは権限の確認が必要です。"
}

// Only initial registration uses direct application. Normal store editing keeps
// its existing candidate-selection modal and shares the same search endpoint.
export default class extends Controller {
  static targets = [
    "intro", "initialAction", "reviewHeader", "reviewHeading", "name", "nameError",
    "details", "content", "loading", "loadingMessage", "resultMessage", "sourcesSection", "sources"
  ]
  static values = { url: String, ready: Boolean, timeout: { type: Number, default: 50000 } }

  connect() {
    this.connected = true
    this.busy = false
    this.applying = false
    this.blockedRegions = []
    this.fields = new Map()
    FIELD_NAMES.forEach((field) => {
      const input = this.element.querySelector(`[name="store[${field}]"]`)
      if (!input) return
      this.fields.set(field, { input, ...this.buildBadge(input), origin: null, sources: [] })
    })
  }

  disconnect() {
    this.connected = false
    this.abortController?.abort()
    this.abortController = null
    window.clearTimeout(this.timeoutId)
    this.unlockPage()
    this.fields.forEach(({ badge }) => badge.remove())
  }

  buildBadge(input) {
    const wrapper = input.closest(".form-floating").parentElement
    wrapper.classList.add("store-registration-setup__field")
    const badge = document.createElement("details")
    badge.className = "store-registration-setup__badge"
    badge.hidden = true
    const summary = document.createElement("summary")
    const explanation = document.createElement("p")
    const label = input.labels?.[0]?.textContent || "項目"
    explanation.id = `${input.id}-ai-explanation`
    summary.setAttribute("aria-describedby", explanation.id)
    summary.setAttribute("aria-label", `${label}のAI入力状況`)
    badge.append(summary, explanation)
    wrapper.append(badge)
    return { badge, summary, explanation }
  }

  edited(event) {
    if (this.applying) return
    if (event.target === this.nameTarget) this.nameErrorTarget.hidden = true
    const entry = Array.from(this.fields.values()).find(({ input }) => input === event.target)
    if (entry) this.setOrigin(entry, null)
  }

  setOrigin(entry, origin) {
    entry.origin = origin
    entry.badge.hidden = !origin
    entry.badge.open = false
    entry.summary.textContent = origin === "ai" ? "AI" : "未"
    entry.explanation.textContent = origin === "ai"
      ? "AIで入力した情報です。内容を確認し、必要に応じて修正してください。"
      : "AIでは確認できませんでした。必要に応じて入力してください。"
  }

  async search(event) {
    event?.preventDefault()
    if (this.busy) return
    const storeName = this.nameTarget.value.trim()
    if (!storeName || [...storeName].length > 255) {
      this.nameErrorTarget.textContent = storeName ? "店舗名を255文字以内で入力してください。" : "店舗名を入力してください"
      this.nameErrorTarget.hidden = false
      this.nameTarget.focus()
      return
    }

    this.nameErrorTarget.hidden = true
    this.setBusy(true, "お店の情報を探しています…")
    const controller = new AbortController()
    this.abortController = controller
    this.timeoutId = window.setTimeout(() => controller.abort(), this.timeoutValue)
    let result = "error"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        credentials: "same-origin",
        body: JSON.stringify({ store_ai_autofill: { store_name: storeName } }),
        signal: controller.signal
      })
      if (!this.connected || this.abortController !== controller) return
      if (response.redirected || [401, 403].includes(response.status)) {
        result = "unauthorized"
      } else {
        const data = await response.json()
        if (!this.connected || this.abortController !== controller) return
        if (response.ok && ["success", "partial", "not_found", "ambiguous"].includes(data.status)) {
          if (["success", "partial"].includes(data.status) && !FIELD_NAMES.every((field) =>
            data.fields?.[field] === null || typeof data.fields?.[field] === "string"
          )) throw new Error("invalid_response")
          result = data.status
          if (["success", "partial"].includes(result)) this.applyResult(data)
        }
      }
    } catch (_) {
      // A timeout, invalid response or network error never clears current data.
      result = "error"
    } finally {
      if (this.abortController === controller) {
        window.clearTimeout(this.timeoutId)
        this.abortController = null
      } else {
        return
      }
      if (this.connected) {
        this.setBusy(false)
        this.showReview(result)
      }
    }
  }

  applyResult(data) {
    const sources = new Map((Array.isArray(data.sources) ? data.sources : [])
      .filter((source) => this.safeUrl(source?.url))
      .map((source) => [source.url, source]))
    this.applying = true
    try {
      this.fields.forEach((entry, field) => {
        if (entry.input.value.trim() && !entry.origin) return
        const value = data.fields?.[field]
        const found = typeof value === "string" && value.trim() !== ""
        entry.input.value = found ? value : ""
        entry.input.dispatchEvent(new Event("input", { bubbles: true }))
        entry.input.dispatchEvent(new Event("change", { bubbles: true }))
        this.setOrigin(entry, found ? "ai" : "missing")
        entry.sources = (Array.isArray(data.field_sources?.[field]) ? data.field_sources[field] : [])
          .filter((url) => found && sources.has(url)).map((url) => sources.get(url))
      })
    } finally {
      this.applying = false
    }
    this.renderSources()
  }

  renderSources() {
    const sources = new Map()
    this.fields.forEach((entry) => entry.sources.forEach((source) => sources.set(source.url, source)))
    this.sourcesTarget.replaceChildren()
    sources.forEach((source) => {
      const item = document.createElement("li")
      const link = document.createElement("a")
      link.href = source.url
      link.textContent = source.title || source.url
      link.target = "_blank"
      link.rel = "noopener noreferrer"
      item.append(link)
      this.sourcesTarget.append(item)
    })
    this.sourcesSectionTarget.hidden = sources.size === 0
  }

  safeUrl(value) {
    try { return ["http:", "https:"].includes(new URL(value).protocol) } catch (_) { return false }
  }

  showReview(result) {
    this.readyValue = true
    this.introTarget.hidden = true
    this.initialActionTarget.hidden = true
    this.reviewHeaderTarget.hidden = false
    this.detailsTarget.hidden = false
    this.detailsTarget.disabled = false
    this.resultMessageTarget.textContent = RESULT_MESSAGES[result] || RESULT_MESSAGES.error
    this.resultMessageTarget.hidden = false
    this.reviewHeadingTarget.focus()
  }

  setBusy(busy, message = "") {
    this.busy = busy
    // inert prevents editing and link/button activation without excluding values
    // from FormData, unlike disabling the form controls while saving.
    this.contentTarget.inert = busy
    if (busy) this.lockPage()
    else this.unlockPage()
    this.element.setAttribute("aria-busy", String(busy))
    this.loadingTarget.hidden = !busy
    this.loadingMessageTarget.textContent = message
    if (busy) this.loadingTarget.focus()
  }

  lockPage() {
    // Keep the shared header/footer from navigating away during the request,
    // just like the existing modal search. The progress message stays usable.
    for (let region = this.element; region?.parentElement && region !== document.body; region = region.parentElement) {
      Array.from(region.parentElement.children).forEach((sibling) => {
        if (sibling === region || sibling.inert) return
        sibling.inert = true
        this.blockedRegions.push(sibling)
      })
    }
  }

  unlockPage() {
    this.blockedRegions.forEach((region) => { region.inert = false })
    this.blockedRegions = []
  }

  guardSubmit(event) {
    if (this.readyValue && !this.busy) return
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  saving() {
    this.setBusy(true, "店舗情報を保存しています…")
  }

  saveFailed() {
    this.setBusy(false)
    this.element.querySelector('[data-image-pair-form-target="error"]')?.focus()
  }
}
