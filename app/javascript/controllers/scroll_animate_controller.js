import { Controller } from "@hotwired/stimulus"

// Animates elements when they scroll into the viewport using IntersectionObserver.
// Usage: data-controller="scroll-animate" on a parent container.
// Children with class "animate-on-scroll" (or variants) will animate in.
// Add "stagger-N" classes for staggered entrance.
export default class extends Controller {
  connect() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible")
            this.observer.unobserve(entry.target)
          }
        })
      },
      { threshold: 0.1, rootMargin: "0px 0px -40px 0px" }
    )

    this.animatedElements.forEach((el) => this.observer.observe(el))
  }

  disconnect() {
    this.observer?.disconnect()
  }

  get animatedElements() {
    return this.element.querySelectorAll(
      ".animate-on-scroll, .animate-on-scroll-left, .animate-on-scroll-right, .animate-on-scroll-scale"
    )
  }
}
