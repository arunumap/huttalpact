import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, delay: { type: Number, default: 1500 } }

  connect() {
    this.timeout = setTimeout(() => {
      Turbo.visit(this.urlValue)
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }
}
