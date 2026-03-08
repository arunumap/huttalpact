import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "icon"]
  static values = { open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.bodyTarget.style.display = this.openValue ? "" : "none"
    if (this.hasIconTarget) {
      this.iconTarget.style.transform = this.openValue ? "rotate(180deg)" : ""
    }
  }
}
