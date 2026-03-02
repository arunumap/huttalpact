import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="model-select"
// Auto-fills cost fields when an AI model is selected from the dropdown.
export default class extends Controller {
  static targets = ["inputCost", "outputCost"]
  static values = { pricing: Object }

  updatePricing(event) {
    const modelId = event.target.value
    const pricing = this.pricingValue[modelId]

    if (pricing) {
      this.inputCostTarget.value = pricing.input
      this.outputCostTarget.value = pricing.output
    }
  }
}
