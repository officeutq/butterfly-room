// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "bootstrap"

function applyStandaloneClass() {
  const isStandalone =
    window.matchMedia("(display-mode: standalone)").matches ||
    window.matchMedia("(display-mode: fullscreen)").matches ||
    window.navigator.standalone === true

  const isIosStandalone = window.navigator.standalone === true

  document.documentElement.classList.toggle("is-standalone", isStandalone)
  document.documentElement.classList.toggle("is-ios-standalone", isIosStandalone)
}

document.addEventListener("turbo:load", applyStandaloneClass)
