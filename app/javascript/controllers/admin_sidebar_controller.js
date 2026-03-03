import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="admin-sidebar"
// Toggles mobile sidebar drawer on the admin layout
export default class extends Controller {
  static targets = ["sidebar", "overlay"]

  toggle() {
    const isOpen = !this.sidebarTarget.classList.contains("-translate-x-full")
    if (isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.sidebarTarget.classList.remove("-translate-x-full")
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden", "lg:overflow-auto")
  }

  close() {
    this.sidebarTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden", "lg:overflow-auto")
  }
}
