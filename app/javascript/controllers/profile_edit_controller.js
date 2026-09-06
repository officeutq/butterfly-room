import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backLink", "bio", "displayName", "saveButton"]

  connect() {
    this.saving = false
    this.initialSnapshot = this.snapshot()
    this.boundBeforeUnload = this.beforeUnload.bind(this)
    window.addEventListener("beforeunload", this.boundBeforeUnload)
    this.refresh()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.boundBeforeUnload)
  }

  refresh() {
    this.dirty = this.snapshot() !== this.initialSnapshot
    this.element.dataset.dirty = String(this.dirty)
    this.saveButtonTarget.disabled = !this.dirty || this.saving
  }

  back(event) {
    if (this.saving) {
      event.preventDefault()
      return
    }
    if (!this.dirty) return
    if (window.confirm("保存していない変更を破棄しますか？")) return

    event.preventDefault()
  }

  prepareSubmit(event) {
    if (!this.dirty || this.saving) {
      event.preventDefault()
      return
    }

    queueMicrotask(() => {
      if (event.imageAttachmentEditorInvalid || event.defaultPrevented) return
      this.setSaving(true)
    })
  }

  imageSubmitStarted() {
    this.setSaving(true)
  }

  imageSubmitFailed() {
    this.setSaving(false)
    this.refresh()
  }

  turboSubmitEnd(event) {
    if (event.detail?.success) return

    this.setSaving(false)
    this.refresh()
  }

  beforeUnload(event) {
    if (!this.dirty || this.saving) return

    event.preventDefault()
    event.returnValue = ""
  }

  snapshot() {
    return JSON.stringify({
      displayName: this.displayNameTarget.value,
      bio: this.bioTarget.value,
      imageOperations: Array.from(this.element.querySelectorAll(
        "input[data-image-attachment-editor-target~='operationInput']"
      )).map((input) => input.value),
    })
  }

  setSaving(saving) {
    this.saving = saving
    if (saving) this.element.setAttribute("aria-busy", "true")
    else this.element.removeAttribute("aria-busy")
    this.saveButtonTarget.disabled = saving || !this.dirty
    this.backLinkTarget.classList.toggle("disabled", saving)
    this.backLinkTarget.setAttribute("aria-disabled", String(saving))
  }
}
