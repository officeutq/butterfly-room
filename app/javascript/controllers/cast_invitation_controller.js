import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static targets = ["error", "status", "retry", "content", "url", "expires", "note", "unsupported", "cancelHelp", "shareButton", "closeButton", "closeLabel"]
  static values = { createUrl: String, storeId: Number, requestKey: String }

  connect() {
    this.invitation = null
    this.completed = false
    this.allowHide = false
    this.shareRecorded = false
    this.issueRejected = false
    this.useCopy = !navigator.share
    this.onHide = (event) => {
      if (!this.allowHide) {
        event.preventDefault()
        this.close()
      }
    }
    this.element.addEventListener("hide.bs.modal", this.onHide)
    this.updateShareLabel()
    this.issue()
  }

  disconnect() {
    this.element.removeEventListener("hide.bs.modal", this.onHide)
  }

  async request(url, method, body = {}) {
    const controller = new AbortController()
    const timeout = window.setTimeout(() => controller.abort(), 15000)
    try {
      const response = await fetch(url, {
        method, credentials: "same-origin",
        signal: controller.signal,
        headers: { "Content-Type": "application/json", "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
        body: JSON.stringify(body)
      })
      const result = await response.json().catch(() => null)
      if (!response.ok) {
        const error = new Error(result?.error || "処理に失敗しました。もう一度お試しください。")
        error.status = response.status
        throw error
      }
      if (!result) throw new Error("処理結果を確認できませんでした。もう一度お試しください。")
      return result
    } catch (error) {
      if (error.name === "AbortError") throw new Error("通信が時間内に完了しませんでした。もう一度お試しください。")
      throw error
    } finally {
      window.clearTimeout(timeout)
    }
  }

  async issue() {
    if (this.busy || this.invitation) return
    this.setBusy(true)
    this.clearError()
    this.retryTarget.hidden = true
    try {
      this.invitation = await this.request(this.createUrlValue, "POST", {
        store_id: this.storeIdValue, request_key: this.requestKeyValue
      })
      if (this.invitation.cancelled) throw new Error("この招待は取消済みです。閉じてから新しく招待してください。")
      this.completed = this.invitation.shared
      this.savedNote = this.invitation.note
      this.noteTarget.value = this.savedNote
      this.urlTarget.value = this.invitation.url
      this.expiresTarget.textContent = this.invitation.expires_at
      this.contentTarget.hidden = false
      this.statusTarget.textContent = "招待URLを発行しました。"
      this.updateCompleted()
      this.notifyStep(this.invitation)
    } catch (error) {
      this.issueRejected = error.status >= 400 && error.status < 500
      this.showError(error.message)
      this.statusTarget.textContent = "発行結果を確認できませんでした。同じ招待の発行を再試行できます。"
      this.retryTarget.hidden = !!this.invitation
    } finally {
      this.setBusy(false)
    }
  }

  async saveNote() {
    const note = this.noteTarget.value
    if (note === this.savedNote) return
    await this.request(this.invitation.update_url, "PATCH", { store_cast_invitation: { note } })
    this.savedNote = note
  }

  // 端末の共有・コピーはクリック直後に呼ぶ。保存通信を先にawaitしない。
  async share() {
    if (this.busy || !this.invitation || this.invitation.cancelled) return
    this.setBusy(true)
    this.clearError()
    const mode = this.useCopy ? "copy" : "share"
    const operation = this.performShare(mode)
    const saving = this.saveNote().then(() => null, (error) => error)
    let operationError = null
    try {
      await operation
      this.completed = true
      this.updateCompleted()
      const guiding = ["invite_cast", "create_invite", "go_dashboard_for_drinks"].includes(this.invitation.step)
      this.statusTarget.textContent = mode === "copy"
        ? "招待URLをコピーしました。LINEなどに貼り付けて、キャスト本人に送ってください。" + (guiding ? "送ったら『閉じる』を押して、次の設定に進みましょう。" : "")
        : guiding
          ? "共有操作が完了したら、『閉じる』を押して、次の設定に進みましょう。"
          : "共有操作が完了しました。相手が承認するまで、この招待URLは有効です（発行から1週間）。"
      await this.recordShared()
    } catch (error) {
      operationError = error
      if (error.name !== "AbortError") {
        if (!this.completed) this.useCopy = true
        this.showError(error.message || "共有に失敗しました。招待URLをコピーして送ってください。")
      }
    }
    const saveError = await saving
    if (saveError) this.showError("メモを保存できませんでした。入力は残っています。もう一度共有・コピーを押すか、共有済みの場合は『閉じる』で保存を再試行してください。")
    if (operationError?.name === "AbortError" && !saveError) this.statusTarget.textContent = "共有を中止しました。招待URLはまだ有効です。"
    this.updateShareLabel()
    this.setBusy(false)
  }

  async performShare(mode) {
    if (mode === "share") {
      // 本文だけを受け取る共有先にもURLを届ける。url欄との重複は避ける。
      return navigator.share({ title: "Butterflyve", text: `${this.invitation.text}\n\n${this.invitation.url}` })
    }
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(this.invitation.url)
    this.urlTarget.focus()
    this.urlTarget.select()
    if (!document.execCommand("copy")) throw new Error("コピーできませんでした。招待URLを選択してコピーしてください。")
  }

  async recordShared() {
    if (this.shareRecorded) return
    const result = await this.request(this.invitation.shared_url, "POST")
    this.shareRecorded = true
    this.notifyStep(result)
  }

  async close() {
    if (this.busy) return
    // 発行応答が失われた場合も同じキーで復旧し、発行済みURLを取り消す。
    if (!this.invitation && !this.issueRejected) {
      await this.issue()
      if (!this.invitation) return
    }
    this.setBusy(true)
    this.clearError()
    try {
      if (this.invitation && this.completed) {
        await this.saveNote()
        await this.recordShared()
      } else if (this.invitation && !this.invitation.cancelled) {
        await this.request(this.invitation.update_url, "DELETE")
      }
      this.allowHide = true
      Modal.getInstance(this.element)?.hide()
    } catch (error) {
      this.showError(error.message)
    } finally {
      this.setBusy(false)
    }
  }

  notifyStep(result) {
    window.dispatchEvent(new CustomEvent("onboarding:update", { detail: { step: result.step, storeId: result.store_id } }))
  }

  updateCompleted() {
    this.element.dataset.onboardingInvitationState = this.completed ? "close" : "share"
    this.element.dataset.onboardingInvitationMode = this.useCopy ? "copy" : "share"
    this.closeLabelTarget.textContent = this.completed ? "閉じる" : "キャンセル"
    this.cancelHelpTarget.hidden = this.completed
    window.dispatchEvent(new CustomEvent("cast-invitation:updated"))
  }

  updateShareLabel() {
    this.shareButtonTarget.textContent = this.useCopy ? "招待URLをコピー" : "招待URLを共有"
    this.unsupportedTarget.hidden = !this.useCopy
  }

  setBusy(value) {
    this.busy = value
    this.shareButtonTarget.disabled = value || !this.invitation || this.invitation.cancelled
    this.closeButtonTargets.forEach((button) => { button.disabled = value })
    this.noteTarget.disabled = value
  }

  clearError() { this.errorTarget.hidden = true }
  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }
}
