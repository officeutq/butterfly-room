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
const DISCLOSURE_FIELDS = new Set(["description", ...URL_FIELDS])
const MAX_STORE_NAME_LENGTH = 255
const ERROR_CODES = new Set([
  "rate_limited",
  "invalid_store_name",
  "openai_rate_limited",
  "timeout",
  "openai_unavailable",
  "invalid_response",
  "configuration_error",
  "unknown_error"
])

export default class extends Controller {
  static targets = [
    "searchButton",
    "modal",
    "title",
    "body",
    "loading",
    "message",
    "errorCode",
    "diagnostics",
    "candidates",
    "sourcesSection",
    "sources",
    "sourcesCount",
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

    const storeName = this.storeNameValue()
    if (storeName === "" || [...storeName].length > MAX_STORE_NAME_LENGTH) {
      this.snapshot = this.captureSnapshot()
      this.renderLoading()
      this.modalInstance().show()
      this.renderState("error", "invalid_store_name")
      return
    }

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
        body: JSON.stringify({ store_ai_autofill: { store_name: storeName } }),
        signal: controller.signal
      })
      const data = await this.readJson(response)
      if (!this.isConnected || this.abortController !== controller) return
      if (!response.ok || data.status === "error") {
        this.renderState("error", data.error_code, data.development_diagnostics)
        return
      }

      this.renderResponse(data)
    } catch (error) {
      if (!this.isConnected || this.abortController !== controller) return
      if (error?.name === "AbortError" && !timedOut) return

      this.renderState("error", error?.name === "AbortError" && timedOut ? "timeout" : "unknown_error")
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
      this.renderState("error", "unknown_error")
      return
    }

    this.visibleCandidates = new Map()
    this.candidatesTarget.replaceChildren()

    const additions = []
    const replacements = []

    FIELD_NAMES.forEach((field) => {
      const value = data.fields?.[field]
      if (typeof value !== "string" || value.trim() === "") return
      if (this.valuesEqual(field, this.snapshot[field] || "", value)) return

      const row = this.buildCandidateRow(field, value)
      const isReplacement = this.normalizedCommon(this.snapshot[field] || "") !== ""
      const group = isReplacement ? replacements : additions
      group.push(row.element)
      this.visibleCandidates.set(field, { value, checkbox: row.checkbox })
    })

    if (additions.length > 0) {
      this.candidatesTarget.append(this.buildCandidateGroup("新しく追加される情報", additions))
    }
    if (replacements.length > 0) {
      this.candidatesTarget.append(this.buildCandidateGroup("既存情報の変更候補", replacements))
    }

    this.renderSources(data.sources)

    if (this.visibleCandidates.size === 0) {
      this.renderState("no_changes")
      return
    }

    this.renderState(data.status)
  }

  buildCandidateGroup(title, rows) {
    const section = document.createElement("section")
    section.className = "store-ai-autofill-group"

    const heading = document.createElement("h3")
    heading.className = "store-ai-autofill-group__heading"
    heading.append(document.createTextNode(title))

    const count = document.createElement("span")
    count.className = "store-ai-autofill-group__count"
    count.textContent = `${rows.length}件`
    heading.append(count)

    const list = document.createElement("div")
    list.className = "store-ai-autofill-list"
    list.append(...rows)
    section.append(heading, list)
    return section
  }

  buildCandidateRow(field, value) {
    const currentValue = this.snapshot[field] || ""
    const isReplacement = this.normalizedCommon(currentValue) !== ""
    const element = document.createElement("section")
    element.className = "store-ai-autofill-candidate"

    const checkbox = document.createElement("input")
    checkbox.type = "checkbox"
    checkbox.className = "form-check-input store-ai-autofill-candidate__checkbox"
    checkbox.id = `store-ai-autofill-${field}`
    checkbox.checked = !isReplacement
    checkbox.addEventListener("change", () => this.updateApplyButton())

    const content = document.createElement("div")

    const header = document.createElement("div")
    header.className = "store-ai-autofill-candidate__header"

    const label = document.createElement("label")
    label.className = "store-ai-autofill-candidate__label"
    label.htmlFor = checkbox.id
    label.textContent = FIELD_LABELS[field]
    header.append(label)

    const badge = document.createElement("span")
    badge.className = "store-ai-autofill-candidate__badge"
    badge.textContent = isReplacement ? "変更" : "追加"
    header.append(badge)
    content.append(header)

    if (isReplacement || DISCLOSURE_FIELDS.has(field)) {
      content.append(this.buildCandidateDetails(field, currentValue, value, isReplacement))
    } else {
      const candidate = document.createElement("div")
      candidate.className = "store-ai-autofill-candidate__value"
      candidate.textContent = this.displayValue(field, value)
      content.append(candidate)
    }

    element.append(checkbox, content)

    return { element, checkbox }
  }

  buildCandidateDetails(field, currentValue, candidateValue, isReplacement) {
    const details = document.createElement("details")
    details.className = "store-ai-autofill-candidate__details"

    const summary = document.createElement("summary")
    summary.textContent = isReplacement ? "変更内容を見る" : "候補内容を見る"
    details.append(summary)

    const comparison = document.createElement("div")
    comparison.className = "store-ai-autofill-candidate__comparison"
    if (isReplacement) {
      comparison.append(this.buildComparisonValue("現在", this.displayValue(field, currentValue)))
    }
    comparison.append(this.buildComparisonValue("AI候補", this.displayValue(field, candidateValue)))
    details.append(comparison)
    return details
  }

  buildComparisonValue(label, value) {
    const wrapper = document.createElement("div")
    const heading = document.createElement("span")
    heading.className = "store-ai-autofill-candidate__comparison-label"
    heading.textContent = label
    const content = document.createElement("div")
    content.className = "store-ai-autofill-candidate__comparison-value"
    content.textContent = value
    wrapper.append(heading, content)
    return wrapper
  }

  renderSources(rawSources) {
    this.sourcesTarget.replaceChildren()
    const sources = Array.isArray(rawSources) ? rawSources : []
    const renderedUrls = new Set()

    sources.forEach((source) => {
      const url = source?.url
      if (!this.safeHttpUrl(url) || renderedUrls.has(url)) return
      renderedUrls.add(url)

      const item = document.createElement("li")
      item.append(this.sourceLink(url, source?.title || url))
      this.sourcesTarget.append(item)
    })

    const sourceCount = this.sourcesTarget.children.length
    this.sourcesCountTarget.textContent = `${sourceCount}件`
    this.sourcesSectionTarget.hidden = sourceCount === 0
    this.sourcesSectionTarget.open = false
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
    this.errorCodeTarget.hidden = true
    this.errorCodeTarget.textContent = ""
    this.diagnosticsTarget.hidden = true
    this.diagnosticsTarget.textContent = ""
    this.candidatesTarget.hidden = true
    this.candidatesTarget.replaceChildren()
    this.sourcesTarget.replaceChildren()
    this.sourcesCountTarget.textContent = ""
    this.sourcesSectionTarget.hidden = true
    this.sourcesSectionTarget.open = false
    this.headerCloseButtonTarget.hidden = true
    this.closeButtonTarget.hidden = true
    this.applyButtonTarget.hidden = true
    this.applyButtonTarget.disabled = false
    this.applyButtonTarget.textContent = "フォームに反映する"
  }

  renderState(state, errorCode = null, diagnostics = null) {
    const errorContent = errorCode === "invalid_store_name"
      ? ["店舗名を確認してください", "店舗名を1〜255文字で入力してから、もう一度お試しください。"]
      : ["検索を完了できませんでした", "時間をおいて、もう一度お試しください。"]
    const content = {
      success: ["店舗情報の候補が見つかりました", "反映する項目を選択してください。未入力の項目は選択済みです。"],
      partial: ["店舗情報の候補が一部見つかりました", "確認できた項目だけを表示しています。反映する項目を選択してください。"],
      not_found: ["店舗情報を確認できませんでした", "公開情報から対象店舗を確認できませんでした。店舗名や現在の登録情報をご確認ください。"],
      ambiguous: ["店舗を特定できませんでした", "同名・類似店舗などがあり、対象店舗を安全に特定できませんでした。"],
      no_changes: ["変更候補はありません", "現在のフォーム値と異なる候補はありませんでした。"],
      error: errorContent,
    }[state] || errorContent

    this.titleTarget.textContent = content[0]
    this.bodyTarget.setAttribute("aria-busy", "false")
    this.loadingTarget.hidden = true
    this.messageTarget.hidden = false
    this.messageTarget.textContent = content[1]
    this.errorCodeTarget.hidden = state !== "error"
    this.errorCodeTarget.textContent = state === "error" ? `エラーコード：${this.displayErrorCode(errorCode)}` : ""
    this.renderDiagnostics(state === "error" ? diagnostics : null)
    this.candidatesTarget.hidden = !["success", "partial"].includes(state)
    this.headerCloseButtonTarget.hidden = false
    this.closeButtonTarget.hidden = false
    this.applyButtonTarget.hidden = !["success", "partial"].includes(state)
    this.closeButtonTarget.textContent = ["success", "partial"].includes(state) ? "キャンセル" : "閉じる"
    if (["success", "partial"].includes(state)) this.updateApplyButton()
  }

  renderDiagnostics(value) {
    const items = [
      ["OpenAI type", value?.openai_type],
      ["OpenAI code", value?.openai_code],
      ["HTTP status", value?.openai_status],
      ["Request ID", value?.request_id]
    ].filter(([, itemValue]) => typeof itemValue === "string" && itemValue !== "")

    this.diagnosticsTarget.hidden = items.length === 0
    this.diagnosticsTarget.textContent = items.length === 0
      ? ""
      : `開発用診断情報\n${items.map(([label, itemValue]) => `${label}: ${itemValue}`).join("\n")}`
  }

  updateApplyButton() {
    const selectedCount = Array.from(this.visibleCandidates.values())
      .filter((candidate) => candidate.checkbox.checked).length
    this.applyButtonTarget.disabled = selectedCount === 0
    this.applyButtonTarget.textContent = selectedCount === 0 ? "項目を選択してください" : `${selectedCount}項目を反映`
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

  displayErrorCode(value) {
    const code = String(value || "")
    return ERROR_CODES.has(code) ? code : "unknown_error"
  }

  storeNameValue() {
    return this.element.querySelector('[name="store[name]"]')?.value?.trim() || ""
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
