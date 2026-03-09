import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "count", "percentage", "needsAttention", "completeButton"]
  static values = { total: Number, reviewed: Number, needsReview: Number }

  connect() {
    this.update()
    this.boundRecount = this.scheduleRecount.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundRecount)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundRecount)
  }

  scheduleRecount() {
    requestAnimationFrame(() => setTimeout(() => this.recount(), 100))
  }

  recount() {
    const allFields = document.querySelectorAll("[data-review-field-status]")
    const reviewed = document.querySelectorAll("[data-review-field-status='reviewed']")
    const needsReview = document.querySelectorAll("[data-needs-review='true'][data-review-field-status='pending']")

    this.totalValue = allFields.length
    this.reviewedValue = reviewed.length
    this.needsReviewValue = needsReview.length

    this.update()
  }

  update() {
    const pct = this.totalValue > 0
      ? Math.round((this.reviewedValue / this.totalValue) * 100)
      : 0

    if (this.hasBarTarget) {
      this.barTarget.style.width = `${pct}%`
      this.barTarget.classList.remove("bg-red-500", "bg-amber-500", "bg-green-500")
      if (pct < 33) {
        this.barTarget.classList.add("bg-red-500")
      } else if (pct < 66) {
        this.barTarget.classList.add("bg-amber-500")
      } else {
        this.barTarget.classList.add("bg-green-500")
      }
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${this.reviewedValue}/${this.totalValue} reviewed`
    }

    if (this.hasPercentageTarget) {
      this.percentageTarget.textContent = `${pct}%`
    }

    if (this.hasNeedsAttentionTarget) {
      if (this.needsReviewValue > 0) {
        this.needsAttentionTarget.textContent =
          `${this.needsReviewValue} need${this.needsReviewValue === 1 ? "s" : ""} attention`
        this.needsAttentionTarget.classList.remove("hidden")
      } else {
        this.needsAttentionTarget.classList.add("hidden")
      }
    }

    if (this.hasCompleteButtonTarget) {
      this.completeButtonTarget.disabled = this.needsReviewValue > 0
      this.completeButtonTarget.classList.toggle("opacity-50", this.needsReviewValue > 0)
      this.completeButtonTarget.classList.toggle("cursor-not-allowed", this.needsReviewValue > 0)
    }
  }
}
