import { Controller } from "@hotwired/stimulus"

// Adds glass-morphism effect and shadow to the navbar on scroll.
// Usage: data-controller="sticky-nav" on the <nav> element.
export default class extends Controller {
  connect() {
    this.scrollHandler = this.onScroll.bind(this)
    window.addEventListener("scroll", this.scrollHandler, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.scrollHandler)
  }

  onScroll() {
    if (window.scrollY > 20) {
      this.element.classList.add("nav-glass-scrolled")
      this.element.classList.remove("nav-glass")
    } else {
      this.element.classList.add("nav-glass")
      this.element.classList.remove("nav-glass-scrolled")
    }
  }
}
