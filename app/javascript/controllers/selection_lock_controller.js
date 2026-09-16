import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]
  static values = { locked: Boolean, storeName: String, boothName: String }

  connect() {
    // 別タブで配信が始まった場合も、選択要求の応答でヘッダーだけを固定する。
    if (this.lockedValue) window.dispatchEvent(new CustomEvent("selection:locked", {
      detail: { storeName: this.storeNameValue, boothName: this.boothNameValue },
    }))
  }

  lock(event) {
    for (const kind of ["store", "booth"]) {
      const name = event?.detail?.[`${kind}Name`]
      if (!name) continue
      this.element.querySelectorAll(`[data-selection-${kind}-name]`).forEach(element => {
        element.textContent = name
        element.classList.remove("text-danger")
      })
    }
    // 名前は残し、マウス・キーボードの両方で操作できない通常表示にする。
    // 終了後の可否は遷移先でサーバーが再判定する。
    this.linkTargets.forEach((link) => link.replaceWith(...link.childNodes))
  }
}
