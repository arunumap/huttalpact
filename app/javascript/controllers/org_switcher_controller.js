import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="org-switcher"
// Toggles the organization switcher dropdown in the sidebar.
export default class extends Controller {
  static targets = ["dropdown", "button", "chevron"]

  connect() {
    this.closeHandler = this.closeOnOutsideClick.bind(this)
    document.addEventListener("click", this.closeHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle("hidden")
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.classList.add("hidden")
    }
  }
}
