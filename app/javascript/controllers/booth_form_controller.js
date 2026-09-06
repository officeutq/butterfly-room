import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backLink", "submitButton"]
  static values = { initialDirty: Boolean }

  connect() {
    this.saving = false
    this.originalSubmitLabels = new WeakMap()
    this.submitButtonTargets.forEach((button) => {
      this.originalSubmitLabels.set(button, button.value)
    })
    this.initialSnapshot = this.snapshot()
    this.boundBeforeUnload = this.beforeUnload.bind(this)
    window.addEventListener("beforeunload", this.boundBeforeUnload)
    this.refresh()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.boundBeforeUnload)
  }

  refresh() {
    this.dirty = this.initialDirtyValue || this.snapshot() !== this.initialSnapshot
    this.element.dataset.dirty = String(this.dirty)
    this.submitButtonTargets.forEach((button) => {
      button.disabled = !this.dirty || this.saving
    })
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
    const controls = Array.from(this.element.elements)
      .filter((control) => this.snapshotControl(control))
      .map((control) => {
        if (control.type === "checkbox" || control.type === "radio") {
          return [control.name, control.type, control.value, control.checked]
        }

        if (control.type === "select-multiple") {
          return [
            control.name,
            control.type,
            Array.from(control.selectedOptions).map((option) => option.value),
          ]
        }

        return [control.name, control.type, control.value]
      })

    return JSON.stringify(controls)
  }

  snapshotControl(control) {
    if (!control.name || control.disabled) return false

    return !["button", "file", "reset", "submit"].includes(control.type)
  }

  setSaving(saving) {
    this.saving = saving
    if (saving) this.element.setAttribute("aria-busy", "true")
    else this.element.removeAttribute("aria-busy")
    this.submitButtonTargets.forEach((button) => {
      button.disabled = saving || !this.dirty
      button.value = saving
        ? (button.dataset.submittingLabel || "保存中…")
        : this.originalSubmitLabels.get(button)
    })
    this.backLinkTarget.classList.toggle("disabled", saving)
    this.backLinkTarget.setAttribute("aria-disabled", String(saving))
  }
}
