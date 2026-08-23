import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["category", "categoryButton"]

  connect() {
    const hashQuestion = window.location.hash.match(/^#faq-q(\d+)$/)
    const selectedCategory = hashQuestion
      ? this.categoryTargets.find((category) => category.querySelector(window.location.hash))
      : this.categoryTargets[0]

    this.showCategory(selectedCategory?.dataset.categoryKey || this.categoryTargets[0]?.dataset.categoryKey)
  }

  selectCategory(event) {
    this.showCategory(event.currentTarget.dataset.categoryKey)
  }

  showCategory(categoryKey) {
    if (!categoryKey) return

    this.categoryTargets.forEach((category) => {
      category.hidden = category.dataset.categoryKey !== categoryKey
    })

    this.categoryButtonTargets.forEach((button) => {
      const selected = button.dataset.categoryKey === categoryKey
      button.setAttribute("aria-pressed", String(selected))
      button.classList.toggle("is-active", selected)
    })
  }
}
