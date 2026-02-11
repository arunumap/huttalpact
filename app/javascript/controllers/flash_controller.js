import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="flash"
// Auto-dismisses flash messages after a timeout, with fade-out animation.
// Close button for immediate dismissal.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.fadeOut(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    if (this.timeout) clearTimeout(this.timeout)
    this.fadeOut()
  }

  fadeOut() {
    this.element.classList.add("transition-opacity", "duration-300", "opacity-0")
    setTimeout(() => this.element.remove(), 300)
  }
}
