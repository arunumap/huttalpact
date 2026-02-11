import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["uploadSection", "formSection"]

  showManualForm() {
    this.uploadSectionTarget.classList.add("hidden")
    this.formSectionTarget.classList.remove("hidden")
  }

  showUploadSection() {
    this.formSectionTarget.classList.add("hidden")
    this.uploadSectionTarget.classList.remove("hidden")
  }
}
