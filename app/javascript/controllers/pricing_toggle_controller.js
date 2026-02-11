import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "monthlyBtn", "annualBtn",
    "starterPrice", "starterPeriod", "starterBtn", "starterAnnualTotal",
    "proPrice", "proPeriod", "proBtn", "proAnnualTotal"
  ]

  selectMonthly() {
    this.monthlyBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.remove("text-gray-500")
    this.annualBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.add("text-gray-500")

    this.#animatePrice(() => {
      this.starterPriceTarget.textContent = "$49"
      this.starterPeriodTarget.textContent = "/month"
      this.proPriceTarget.textContent = "$149"
      this.proPeriodTarget.textContent = "/month"

      if (this.hasStarterAnnualTotalTarget) this.starterAnnualTotalTarget.classList.add("hidden")
      if (this.hasProAnnualTotalTarget) this.proAnnualTotalTarget.classList.add("hidden")
    })

    this.updateButtons("monthly")
  }

  selectAnnual() {
    this.annualBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.remove("text-gray-500")
    this.monthlyBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.add("text-gray-500")

    this.#animatePrice(() => {
      this.starterPriceTarget.textContent = "$41"
      this.starterPeriodTarget.textContent = "/month, billed annually"
      this.proPriceTarget.textContent = "$124"
      this.proPeriodTarget.textContent = "/month, billed annually"

      if (this.hasStarterAnnualTotalTarget) this.starterAnnualTotalTarget.classList.remove("hidden")
      if (this.hasProAnnualTotalTarget) this.proAnnualTotalTarget.classList.remove("hidden")
    })

    this.updateButtons("annual")
  }

  updateButtons(period) {
    if (this.hasStarterBtnTarget) {
      const btn = this.starterBtnTarget
      const priceParam = period === "annual"
        ? btn.dataset.pricingToggleAnnualPriceParam
        : btn.dataset.pricingToggleMonthlyPriceParam
      const input = btn.closest("form")?.querySelector("input[name='price_id']")
      if (input) input.value = priceParam
    }

    if (this.hasProBtnTarget) {
      const btn = this.proBtnTarget
      const priceParam = period === "annual"
        ? btn.dataset.pricingToggleAnnualPriceParam
        : btn.dataset.pricingToggleMonthlyPriceParam
      const input = btn.closest("form")?.querySelector("input[name='price_id']")
      if (input) input.value = priceParam
    }
  }

  #animatePrice(updateFn) {
    const targets = [this.starterPriceTarget, this.proPriceTarget]
    targets.forEach(t => t.classList.add("opacity-0"))

    setTimeout(() => {
      updateFn()
      targets.forEach(t => t.classList.remove("opacity-0"))
    }, 150)
  }
}
