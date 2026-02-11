import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "dropdown", "list"]

  connect() {
    this.clickOutsideHandler = this.clickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutsideHandler)
  }

  toggle(event) {
    event.stopPropagation()

    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
    document.addEventListener("click", this.clickOutsideHandler)
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    document.removeEventListener("click", this.clickOutsideHandler)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
}
