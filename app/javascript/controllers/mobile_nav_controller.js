import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mobile-nav"
// Toggles mobile hamburger menu on marketing/pricing pages
export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }
}
