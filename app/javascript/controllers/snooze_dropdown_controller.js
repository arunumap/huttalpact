import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.clickOutsideHandler = this.clickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
  }

  toggle(event) {
    event.stopPropagation()

    if (this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.remove("hidden")
      document.addEventListener("click", this.clickOutsideHandler)
    } else {
      this.menuTarget.classList.add("hidden")
      document.removeEventListener("click", this.clickOutsideHandler)
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
      document.removeEventListener("click", this.clickOutsideHandler)
    }
  }
}
