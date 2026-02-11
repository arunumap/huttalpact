import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Toggles mobile sidebar with overlay. On desktop (lg+), sidebar is always visible.
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

  // Close sidebar when clicking a nav link (mobile)
  navigate() {
    if (window.innerWidth < 1024) {
      this.close()
    }
  }
}
