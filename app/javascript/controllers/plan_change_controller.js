import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["monthlyBtn", "annualBtn", "planCard"]

  connect() {
    this.#applyPeriod("monthly")
  }

  selectMonthly() {
    this.monthlyBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.remove("text-gray-500")
    this.annualBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.add("text-gray-500")

    this.#applyPeriod("monthly")
  }

  selectAnnual() {
    this.annualBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.remove("text-gray-500")
    this.monthlyBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.add("text-gray-500")

    this.#applyPeriod("annual")
  }

  #applyPeriod(period) {
    this.planCardTargets.forEach((card) => {
      const monthlyPrice = card.dataset.planChangeMonthlyPrice
      const annualPrice = card.dataset.planChangeAnnualPrice || monthlyPrice
      const monthlyPeriod = card.dataset.planChangeMonthlyPeriod || "/month"
      const annualPeriod = card.dataset.planChangeAnnualPeriod || monthlyPeriod
      const monthlyKey = card.dataset.planChangeMonthlyKey
      const annualKey = card.dataset.planChangeAnnualKey || monthlyKey

      const priceEl = card.querySelector("[data-plan-change-role='price']")
      const periodEl = card.querySelector("[data-plan-change-role='period']")
      const annualTotalEl = card.querySelector("[data-plan-change-role='annual-total']")
      const lookupInputs = card.querySelectorAll("input[data-plan-change-role='lookup-input']")

      const showAnnual = period === "annual" && annualPrice !== monthlyPrice

      if (priceEl) priceEl.textContent = showAnnual ? annualPrice : monthlyPrice
      if (periodEl) periodEl.textContent = showAnnual ? annualPeriod : monthlyPeriod

      if (annualTotalEl) {
        if (showAnnual) {
          annualTotalEl.classList.remove("hidden")
        } else {
          annualTotalEl.classList.add("hidden")
        }
      }

      lookupInputs.forEach((input) => {
        const key = period === "annual" ? annualKey : monthlyKey
        if (key) {
          input.value = key
        }
      })
    })
  }
}
