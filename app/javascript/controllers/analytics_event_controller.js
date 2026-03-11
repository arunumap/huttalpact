import { Controller } from "@hotwired/stimulus"

// Fires a Google Analytics event when appended to the DOM via Turbo Stream,
// then removes itself. Use the shared/_analytics_event partial to render it.
export default class extends Controller {
  static values = { name: String, params: Object }

  connect() {
    if (typeof gtag === "function") {
      gtag("event", this.nameValue, this.paramsValue || {})
    }
    this.element.remove()
  }
}
