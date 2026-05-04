import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "favoritesDepot",
    "liveRoot",
    "waitingRoot",
    "boothFavoriteAnchor",
    "storeFavoriteAnchor",
    "userFavoriteAnchor",
  ]

  connect() {
    this._wasLiveLike = null

    this._observer = new MutationObserver(() => this._sync())
    this._observer.observe(this.element, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["data-live-like", "class"],
    })

    this._sync()
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
  }

  _sync() {
    const marker = this.element.querySelector("#stream_state [data-live-like]")
    const liveLike = marker?.getAttribute("data-live-like") === "true"
    const becameLive = this._wasLiveLike === false && liveLike

    this.element.classList.toggle("is-live", liveLike)

    if (this.hasLiveRootTarget) {
      this.liveRootTarget.classList.toggle("d-none", !liveLike)
    }

    if (this.hasWaitingRootTarget) {
      this.waitingRootTarget.classList.toggle("d-none", liveLike)
    }

    if (becameLive) {
      this._clearFlash()
    }

    this._wasLiveLike = liveLike

    this._mountFavorites(liveLike)
  }

  _clearFlash() {
    const flashInner = document.getElementById("flash_inner")
    if (!flashInner) return

    flashInner.replaceChildren()
  }

  _mountFavorites(liveLike) {
    if (!this.hasFavoritesDepotTarget) return

    const boothButton = this.element.querySelector("#booth_favorite_button")
    const storeButton = this.element.querySelector("#store_favorite_button")
    const userButton = this.element.querySelector("#user_favorite_button")

    if (liveLike) {
      this._moveToDepot(boothButton)
      this._moveToDepot(storeButton)
      this._moveToDepot(userButton)

      return
    }

    if (boothButton && this.hasBoothFavoriteAnchorTarget && boothButton.parentElement !== this.boothFavoriteAnchorTarget) {
      this.boothFavoriteAnchorTarget.replaceChildren(boothButton)
    }

    if (storeButton && this.hasStoreFavoriteAnchorTarget && storeButton.parentElement !== this.storeFavoriteAnchorTarget) {
      this.storeFavoriteAnchorTarget.replaceChildren(storeButton)
    }

    if (userButton && this.hasUserFavoriteAnchorTarget && userButton.parentElement !== this.userFavoriteAnchorTarget) {
      this.userFavoriteAnchorTarget.replaceChildren(userButton)
    }
  }

  _moveToDepot(button) {
    if (button && button.parentElement !== this.favoritesDepotTarget) {
      this.favoritesDepotTarget.appendChild(button)
    }
  }
}
