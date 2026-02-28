import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "monthlyBtn", "annualBtn",
    "starterPrice", "starterPeriod", "starterAnnualTotal", "starterBtn",
    "proPrice", "proPeriod", "proAnnualTotal", "proBtn"
  ]

  selectMonthly() {
    this.monthlyBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.remove("text-gray-500")
    this.annualBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.add("text-gray-500")

    if (this.hasStarterPriceTarget) this.starterPriceTarget.textContent = "$49"
    if (this.hasStarterPeriodTarget) this.starterPeriodTarget.textContent = "/month"
    if (this.hasStarterAnnualTotalTarget) this.starterAnnualTotalTarget.classList.add("hidden")

    if (this.hasProPriceTarget) this.proPriceTarget.textContent = "$149"
    if (this.hasProPeriodTarget) this.proPeriodTarget.textContent = "/month"
    if (this.hasProAnnualTotalTarget) this.proAnnualTotalTarget.classList.add("hidden")

    this.#updateLookupKeys("monthly")
  }

  selectAnnual() {
    this.annualBtnTarget.classList.add("bg-white", "text-gray-900", "shadow-sm")
    this.annualBtnTarget.classList.remove("text-gray-500")
    this.monthlyBtnTarget.classList.remove("bg-white", "text-gray-900", "shadow-sm")
    this.monthlyBtnTarget.classList.add("text-gray-500")

    if (this.hasStarterPriceTarget) this.starterPriceTarget.textContent = "$41"
    if (this.hasStarterPeriodTarget) this.starterPeriodTarget.textContent = "/month, billed annually"
    if (this.hasStarterAnnualTotalTarget) this.starterAnnualTotalTarget.classList.remove("hidden")

    if (this.hasProPriceTarget) this.proPriceTarget.textContent = "$124"
    if (this.hasProPeriodTarget) this.proPeriodTarget.textContent = "/month, billed annually"
    if (this.hasProAnnualTotalTarget) this.proAnnualTotalTarget.classList.remove("hidden")

    this.#updateLookupKeys("annual")
  }

  #updateLookupKeys(period) {
    if (this.hasStarterBtnTarget) {
      this.starterBtnTargets.forEach((el) => {
        const key = period === "annual"
          ? el.dataset.planChangeAnnualKeyParam
          : el.dataset.planChangeMonthlyKeyParam
        if (key) el.value = key
      })
    }

    if (this.hasProBtnTarget) {
      this.proBtnTargets.forEach((el) => {
        const key = period === "annual"
          ? el.dataset.planChangeAnnualKeyParam
          : el.dataset.planChangeMonthlyKeyParam
        if (key) el.value = key
      })
    }
  }
}
