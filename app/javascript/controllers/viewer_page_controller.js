import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "favoritesDepot",
    "liveRoot",
    "waitingRoot",
    "boothFavoriteAnchor",
    "storeFavoriteAnchor",
  ]

  connect() {
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

    this.element.classList.toggle("is-live", liveLike)

    if (this.hasLiveRootTarget) {
      this.liveRootTarget.classList.toggle("d-none", !liveLike)
    }

    if (this.hasWaitingRootTarget) {
      this.waitingRootTarget.classList.toggle("d-none", liveLike)
    }

    this._mountFavorites(liveLike)
  }

  _mountFavorites(liveLike) {
    if (!this.hasFavoritesDepotTarget) return

    const boothButton = this.element.querySelector("#booth_favorite_button")
    const storeButton = this.element.querySelector("#store_favorite_button")

    if (liveLike) {
      if (boothButton && boothButton.parentElement !== this.favoritesDepotTarget) {
        this.favoritesDepotTarget.appendChild(boothButton)
      }

      if (storeButton && storeButton.parentElement !== this.favoritesDepotTarget) {
        this.favoritesDepotTarget.appendChild(storeButton)
      }

      return
    }

    if (boothButton && this.hasBoothFavoriteAnchorTarget && boothButton.parentElement !== this.boothFavoriteAnchorTarget) {
      this.boothFavoriteAnchorTarget.replaceChildren(boothButton)
    }

    if (storeButton && this.hasStoreFavoriteAnchorTarget && storeButton.parentElement !== this.storeFavoriteAnchorTarget) {
      this.storeFavoriteAnchorTarget.replaceChildren(storeButton)
    }
  }
}
