import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error"]

  connect() {
    this.preventBusyClose = (event) => { if (this.busy) event.preventDefault() }
    this.element.addEventListener("hide.bs.modal", this.preventBusyClose)
  }

  disconnect() {
    this.element.removeEventListener("hide.bs.modal", this.preventBusyClose)
    this.disconnected = true
  }

  async submit(event) {
    event.preventDefault()
    if (this.busy) return
    if (this.hasUnsavedChanges() && !window.confirm("保存していない変更を破棄しますか？")) return

    const form = event.target
    this.setBusy(true)
    this.errorTarget.hidden = true
    try {
      const response = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
      })
      const result = await response.json()
      if (this.disconnected) return
      if (!response.ok || !result.redirect_url) {
        throw new Error(result.message || "切り替えできませんでした。再度お試しください")
      }
      window.Turbo.cache.clear()
      if (result.frame === "modal") {
        for (const kind of ["store", "booth"]) {
          document.querySelectorAll(`[data-selection-${kind}-name]`).forEach((element) => {
            element.textContent = result[`${kind}_name`] || "未選択"
            element.classList.toggle("text-danger", !result[`${kind}_name`])
          })
        }
        document.getElementById("modal").src = result.redirect_url
      } else {
        window.Turbo.visit(result.redirect_url)
      }
    } catch (error) {
      this.errorTarget.textContent = error.message || "通信に失敗しました。再度お試しください"
      this.errorTarget.hidden = false
      this.setBusy(false)
    }
  }

  hasUnsavedChanges() {
    return Array.from(document.forms).some((form) => {
      if (this.element.contains(form) || form.closest("#modal") || form.method.toLowerCase() === "get") return false
      // 画像編集を含む既存フォームは、そのフォーム自身の変更判定を使う。
      if (form.dataset.dirty !== undefined) return form.dataset.dirty === "true"
      return Array.from(form.elements).some((control) => {
        if (!control.name || control.disabled || ["hidden", "button", "reset", "submit"].includes(control.type)) return false
        if (control.type === "file") return control.files.length > 0
        if (["checkbox", "radio"].includes(control.type)) return control.checked !== control.defaultChecked
        if (control.type.startsWith("select-")) {
          const options = Array.from(control.options)
          const hasDefault = options.some((option) => option.defaultSelected)
          return options.some((option, index) => option.selected !== (option.defaultSelected || (!hasDefault && control.type === "select-one" && index === 0)))
        }
        return control.value !== control.defaultValue
      })
    })
  }

  setBusy(busy) {
    this.busy = busy
    if (busy) {
      this.disabledButtons = Array.from(this.element.querySelectorAll("button, input[type=submit]"))
        .filter((button) => !button.disabled)
    }
    this.disabledButtons.forEach((button) => { button.disabled = busy })
    this.element.setAttribute("aria-busy", String(busy))
  }
}
