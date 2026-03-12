import { Controller } from "@hotwired/stimulus"

// Animates a number counting up from 0 to a target value when visible.
// Usage: <span data-controller="counter" data-counter-target-value="40" data-counter-suffix-value="+">0</span>
export default class extends Controller {
  static values = {
    target: Number,
    suffix: { type: String, default: "" },
    prefix: { type: String, default: "" },
    duration: { type: Number, default: 1500 }
  }

  connect() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.animate()
            this.observer.unobserve(entry.target)
          }
        })
      },
      { threshold: 0.3 }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  animate() {
    const target = this.targetValue
    const duration = this.durationValue
    const start = performance.now()

    const step = (now) => {
      const elapsed = now - start
      const progress = Math.min(elapsed / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3) // ease-out cubic
      const current = Math.round(eased * target)

      this.element.textContent = `${this.prefixValue}${current.toLocaleString()}${this.suffixValue}`

      if (progress < 1) {
        requestAnimationFrame(step)
      }
    }

    requestAnimationFrame(step)
  }
}
