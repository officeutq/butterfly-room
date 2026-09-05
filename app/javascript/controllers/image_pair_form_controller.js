import { Controller } from "@hotwired/stimulus"
import { ImagePairMultipartClient } from "image_attachments/multipart_client"

export default class extends Controller {
  static targets = ["error", "submitButton"]

  connect() {
    this.client = new ImagePairMultipartClient()
    this.submitting = false
    this.isDisconnected = false
  }

  disconnect() {
    this.isDisconnected = true
    this.client?.abort()
    this.client = null
  }

  submit(event) {
    if (!this.hasImageOperation()) return

    event.preventDefault()
    if (this.submitting) return

    // The editor controllers validate the same submit event. Defer the XHR
    // until every editor has had a chance to mark an unfinished payload.
    queueMicrotask(() => {
      if (event.imageAttachmentEditorInvalid || this.isDisconnected || this.submitting) return
      if (!this.confirmSubmission(event)) return

      this.submitMultipartForm()
    })
  }

  async submitMultipartForm() {
    this.submitting = true
    this.setSubmitting(true)
    this.clearError()
    this.renderEditorStatuses("画像と入力内容を保存しています…")

    try {
      const result = await this.client.submit({
        url: this.element.action,
        method: this.element.method.toUpperCase(),
        body: new FormData(this.element),
      })
      if (this.isDisconnected) return

      const redirect = this.sameOriginRedirect(result.redirect_url)
      window.location.assign(redirect)
    } catch (error) {
      if (this.isDisconnected) return

      this.renderError(error.message || "画像を保存できませんでした。再度保存してください。")
      this.renderEditorStatuses("保存できませんでした。内容を確認して再度保存してください。", true)
      this.setSubmitting(false)
      this.submitting = false
    }
  }

  hasImageOperation() {
    return this.operationInputs().some((input) => input.value.length > 0)
  }

  confirmSubmission(event) {
    const message = event.submitter?.dataset?.turboConfirm
    return !message || window.confirm(message)
  }

  operationInputs() {
    return Array.from(this.element.querySelectorAll(
      "input[data-image-attachment-editor-target~='operationInput']"
    ))
  }

  changedEditors() {
    return this.operationInputs()
      .filter((input) => input.value.length > 0)
      .map((input) => input.closest("[data-controller~='image-attachment-editor']"))
      .filter(Boolean)
  }

  renderEditorStatuses(message, error = false) {
    this.changedEditors().forEach((editor) => {
      const status = editor.querySelector("[data-image-attachment-editor-target~='status']")
      if (!status) return

      status.textContent = message
      status.classList.toggle("text-danger", error)
    })
  }

  setSubmitting(submitting) {
    if (submitting) this.element.setAttribute("aria-busy", "true")
    else this.element.removeAttribute("aria-busy")

    this.submitButtonTargets.forEach((button) => {
      button.disabled = submitting
    })
  }

  clearError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  renderError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
    this.errorTarget.focus()
  }

  sameOriginRedirect(value) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("保存結果を確認できませんでした。画面を読み直してください。")
    }

    const redirect = new URL(value, window.location.origin)
    if (redirect.origin !== window.location.origin) {
      throw new Error("保存結果を確認できませんでした。画面を読み直してください。")
    }

    return redirect.href
  }
}
