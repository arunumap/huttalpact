import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "passwordInput", "submitBtn"]

  toggle() {
    this.formTarget.classList.toggle("hidden")
    if (!this.formTarget.classList.contains("hidden")) {
      this.passwordInputTarget.focus()
    } else {
      this.passwordInputTarget.value = ""
      this.submitBtnTarget.disabled = true
    }
  }

  validatePassword() {
    this.submitBtnTarget.disabled = this.passwordInputTarget.value.trim().length === 0
  }

  // Hide form on Escape key
  keydown(event) {
    if (event.key === "Escape" && !this.formTarget.classList.contains("hidden")) {
      this.toggle()
    }
  }

  connect() {
    this.element.addEventListener("keydown", this.keydown.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.keydown.bind(this))
  }
}
