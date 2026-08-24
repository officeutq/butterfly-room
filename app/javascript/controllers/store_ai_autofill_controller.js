import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

const FIELD_NAMES = [
  "description",
  "area",
  "business_type",
  "address",
  "phone_number",
  "business_hours",
  "website_url",
  "x_url",
  "instagram_url",
  "tiktok_url",
  "youtube_url"
]

const FIELD_LABELS = {
  description: "概要",
  area: "地域",
  business_type: "業態",
  address: "住所",
  phone_number: "電話番号",
  business_hours: "営業時間",
  website_url: "ホームページURL",
  x_url: "X URL",
  instagram_url: "Instagram URL",
  tiktok_url: "TikTok URL",
  youtube_url: "YouTube URL"
}

const BUSINESS_TYPE_LABELS = {
  cabaret: "キャバクラ",
  girls_bar: "ガールズバー",
  snack: "スナック",
  lounge: "ラウンジ",
  concept_cafe: "コンカフェ",
  other: "その他"
}

const URL_FIELDS = ["website_url", "x_url", "instagram_url", "tiktok_url", "youtube_url"]

export default class extends Controller {
  static targets = [
    "searchButton",
    "modal",
    "title",
    "body",
    "loading",
    "message",
    "candidates",
    "sourcesSection",
    "sources",
    "headerCloseButton",
    "closeButton",
    "applyButton"
  ]

  static values = {
    url: String,
    timeout: { type: Number, default: 50000 }
  }

  connect() {
    this.modal = null
    this.requestInFlight = false
    this.abortController = null
    this.timeoutId = null
    this.snapshot = {}
    this.visibleCandidates = new Map()
    this.isConnected = true
    this.handleBeforeCache = this.cleanup.bind(this)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
  }

  disconnect() {
    this.isConnected = false
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    this.cleanup()
  }

  async search(event) {
    event?.preventDefault()
    if (this.requestInFlight) return

    this.requestInFlight = true
    this.searchButtonTarget.disabled = true
    this.snapshot = this.captureSnapshot()
    this.renderLoading()
    this.modalInstance().show()

    const controller = new AbortController()
    this.abortController = controller
    let timedOut = false
    this.timeoutId = window.setTimeout(() => {
      timedOut = true
      controller.abort()
    }, this.timeoutValue)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: this.requestHeaders(),
        credentials: "same-origin",
        body: "{}",
        signal: controller.signal
      })
      const data = await this.readJson(response)
      if (!response.ok || data.status === "error") throw new Error("store_ai_autofill_failed")
      if (!this.isConnected || this.abortController !== controller) return

      this.renderResponse(data)
    } catch (error) {
      if (!this.isConnected || this.abortController !== controller) return
      if (error?.name === "AbortError" && !timedOut) return

      this.renderState("error")
    } finally {
      if (this.timeoutId) window.clearTimeout(this.timeoutId)
      this.timeoutId = null

      if (this.abortController === controller) {
        this.abortController = null
        this.requestInFlight = false
        if (this.isConnected) this.searchButtonTarget.disabled = false
      }
    }
  }

  close(event) {
    event?.preventDefault()
    if (this.requestInFlight) return

    this.modal?.hide()
  }

  apply(event) {
    event?.preventDefault()
    if (this.requestInFlight) return

    this.visibleCandidates.forEach((candidate, field) => {
      if (!candidate.checkbox.checked) return

      const input = this.formField(field)
      if (!input) return

      input.value = candidate.value
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.dispatchEvent(new Event("change", { bubbles: true }))
    })

    this.modal?.hide()
  }

  captureSnapshot() {
    return Object.fromEntries(
      FIELD_NAMES.map((field) => [field, this.formField(field)?.value || ""])
    )
  }

  renderResponse(data) {
    if (data.status === "not_found" || data.status === "ambiguous") {
      this.renderSources(data.sources)
      this.renderState(data.status)
      return
    }

    if (!["success", "partial"].includes(data.status)) {
      this.renderState("error")
      return
    }

    this.visibleCandidates = new Map()
    this.candidatesTarget.replaceChildren()

    FIELD_NAMES.forEach((field) => {
      const value = data.fields?.[field]
      if (typeof value !== "string" || value.trim() === "") return
      if (this.valuesEqual(field, this.snapshot[field] || "", value)) return

      const row = this.buildCandidateRow(
        field,
        value,
        Array.isArray(data.field_sources?.[field]) ? data.field_sources[field] : []
      )
      this.candidatesTarget.append(row.element)
      this.visibleCandidates.set(field, { value, checkbox: row.checkbox })
    })

    this.renderSources(data.sources)

    if (this.visibleCandidates.size === 0) {
      this.renderState("no_changes")
      return
    }

    this.renderState(data.status)
  }

  buildCandidateRow(field, value, sourceUrls) {
    const element = document.createElement("section")
    element.className = "border rounded p-3 mb-3"

    const checkWrapper = document.createElement("div")
    checkWrapper.className = "form-check mb-2"

    const checkbox = document.createElement("input")
    checkbox.type = "checkbox"
    checkbox.className = "form-check-input"
    checkbox.id = `store-ai-autofill-${field}`
    checkbox.checked = this.normalizedCommon(this.snapshot[field] || "") === ""

    const label = document.createElement("label")
    label.className = "form-check-label fw-semibold"
    label.htmlFor = checkbox.id
    label.textContent = FIELD_LABELS[field]
    checkWrapper.append(checkbox, label)

    const current = document.createElement("div")
    current.className = "small text-body-secondary mb-1"
    current.textContent = `現在値: ${this.displayValue(field, this.snapshot[field]) || "（未入力）"}`

    const candidate = document.createElement("div")
    candidate.className = "text-break"
    candidate.textContent = `AI候補: ${this.displayValue(field, value)}`

    element.append(checkWrapper, current, candidate)

    const links = this.buildSourceLinks(sourceUrls)
    if (links) element.append(links)

    return { element, checkbox }
  }

  buildSourceLinks(urls) {
    const safeUrls = urls.filter((url) => this.safeHttpUrl(url))
    if (safeUrls.length === 0) return null

    const wrapper = document.createElement("div")
    wrapper.className = "small mt-2"
    const prefix = document.createElement("span")
    prefix.textContent = "情報源: "
    wrapper.append(prefix)

    safeUrls.forEach((url, index) => {
      if (index > 0) wrapper.append(document.createTextNode(" / "))
      wrapper.append(this.sourceLink(url, `情報源${index + 1}`))
    })
    return wrapper
  }

  renderSources(rawSources) {
    this.sourcesTarget.replaceChildren()
    const sources = Array.isArray(rawSources) ? rawSources : []

    sources.forEach((source) => {
      const url = source?.url
      if (!this.safeHttpUrl(url)) return

      const item = document.createElement("li")
      item.append(this.sourceLink(url, source?.title || url))
      this.sourcesTarget.append(item)
    })

    this.sourcesSectionTarget.hidden = this.sourcesTarget.children.length === 0
  }

  sourceLink(url, label) {
    const link = document.createElement("a")
    link.href = url
    link.target = "_blank"
    link.rel = "noopener noreferrer"
    link.textContent = label
    return link
  }

  renderLoading() {
    this.visibleCandidates = new Map()
    this.titleTarget.textContent = "AI店舗情報検索"
    this.bodyTarget.setAttribute("aria-busy", "true")
    this.loadingTarget.hidden = false
    this.messageTarget.hidden = true
    this.messageTarget.textContent = ""
    this.candidatesTarget.hidden = true
    this.candidatesTarget.replaceChildren()
    this.sourcesTarget.replaceChildren()
    this.sourcesSectionTarget.hidden = true
    this.headerCloseButtonTarget.hidden = true
    this.closeButtonTarget.hidden = true
    this.applyButtonTarget.hidden = true
  }

  renderState(state) {
    const content = {
      success: ["店舗情報の候補が見つかりました", "反映する項目を選択してください。未入力の項目は選択済みです。"],
      partial: ["店舗情報の候補が一部見つかりました", "確認できた項目だけを表示しています。反映する項目を選択してください。"],
      not_found: ["店舗情報を確認できませんでした", "公開情報から対象店舗を確認できませんでした。店舗名や現在の登録情報をご確認ください。"],
      ambiguous: ["店舗を特定できませんでした", "同名・類似店舗などがあり、対象店舗を安全に特定できませんでした。"],
      no_changes: ["変更候補はありません", "現在のフォーム値と異なる候補はありませんでした。"],
      error: ["検索を完了できませんでした", "時間をおいて、もう一度お試しください。"],
    }[state] || ["検索を完了できませんでした", "時間をおいて、もう一度お試しください。"]

    this.titleTarget.textContent = content[0]
    this.bodyTarget.setAttribute("aria-busy", "false")
    this.loadingTarget.hidden = true
    this.messageTarget.hidden = false
    this.messageTarget.textContent = content[1]
    this.candidatesTarget.hidden = !["success", "partial"].includes(state)
    this.headerCloseButtonTarget.hidden = false
    this.closeButtonTarget.hidden = false
    this.applyButtonTarget.hidden = !["success", "partial"].includes(state)
    this.closeButtonTarget.textContent = ["success", "partial"].includes(state) ? "キャンセル" : "閉じる"
  }

  valuesEqual(field, current, candidate) {
    if (field === "phone_number") {
      return this.normalizePhone(current) === this.normalizePhone(candidate)
    }
    if (URL_FIELDS.includes(field)) {
      return this.normalizeUrl(current) === this.normalizeUrl(candidate)
    }
    if (field === "business_type") return current === candidate

    return this.normalizedCommon(current) === this.normalizedCommon(candidate)
  }

  normalizedCommon(value) {
    return String(value || "").normalize("NFKC").replace(/\r\n?/g, "\n").trim()
  }

  normalizePhone(value) {
    return String(value || "").replace(/\D/g, "")
  }

  normalizeUrl(value) {
    const normalized = this.normalizedCommon(value)
    if (normalized === "") return ""

    try {
      const url = new URL(normalized)
      if (!["http:", "https:"].includes(url.protocol)) return normalized
      url.hash = ""
      if ((url.protocol === "http:" && url.port === "80") || (url.protocol === "https:" && url.port === "443")) {
        url.port = ""
      }
      url.pathname = url.pathname.replace(/\/+$/, "")
      return url.toString().replace(/\/$/, "")
    } catch (_) {
      return normalized
    }
  }

  safeHttpUrl(value) {
    try {
      return ["http:", "https:"].includes(new URL(String(value)).protocol)
    } catch (_) {
      return false
    }
  }

  displayValue(field, value) {
    if (field === "business_type") return BUSINESS_TYPE_LABELS[value] || value || ""
    return value || ""
  }

  formField(field) {
    if (!FIELD_NAMES.includes(field)) return null
    return this.element.querySelector(`[name="store[${field}]"]`)
  }

  requestHeaders() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const headers = {
      Accept: "application/json",
      "Content-Type": "application/json"
    }
    if (token) headers["X-CSRF-Token"] = token
    return headers
  }

  async readJson(response) {
    try {
      return await response.json()
    } catch (_) {
      throw new Error("invalid_json")
    }
  }

  modalInstance() {
    this.modal ||= new Modal(this.modalTarget, { backdrop: "static", keyboard: false })
    return this.modal
  }

  cleanup() {
    if (this.timeoutId) window.clearTimeout(this.timeoutId)
    this.timeoutId = null
    this.abortController?.abort()
    this.abortController = null
    this.requestInFlight = false
    try { this.modal?.dispose() } catch (_) {}
    this.modal = null
    this.cleanupBootstrapModalState()
    if (this.hasSearchButtonTarget) this.searchButtonTarget.disabled = false
  }

  cleanupBootstrapModalState() {
    document.querySelectorAll?.(".modal-backdrop").forEach((element) => element.remove())
    document.body?.classList?.remove("modal-open")
    document.body?.style?.removeProperty("padding-right")
    document.body?.style?.removeProperty("overflow")
  }
}
