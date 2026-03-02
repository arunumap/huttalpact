import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "commentSection", "submitSection"]

  toggleForm() {
    this.formTarget.classList.toggle("hidden")
  }

  selectRating() {
    this.commentSectionTarget.classList.remove("hidden")
    this.submitSectionTarget.classList.remove("hidden")
  }
}
