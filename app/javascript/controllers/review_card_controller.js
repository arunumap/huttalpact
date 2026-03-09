import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editForm", "arrayChevron", "arrayDetail"]
  static values = { fieldId: String }

  toggleEdit() {
    if (!this.hasEditFormTarget) return

    const isHidden = this.editFormTarget.classList.toggle("hidden")

    // Auto-focus the first input when opening
    if (!isHidden) {
      const input = this.editFormTarget.querySelector("input, textarea, select")
      if (input) input.focus()
    }
  }

  toggleArray() {
    if (!this.hasArrayDetailTarget) return

    this.arrayDetailTarget.classList.toggle("hidden")

    if (this.hasArrayChevronTarget) {
      this.arrayChevronTarget.classList.toggle("rotate-90")
    }
  }

  focusSource(event) {
    const blockquote = event.currentTarget.closest("[data-source-excerpt]") || event.currentTarget
    const documentId = blockquote.dataset.sourceDocumentId || blockquote.dataset.documentSource
    const startOffset = Number.parseInt(blockquote.dataset.sourceStart, 10)
    const endOffset = Number.parseInt(blockquote.dataset.sourceEnd, 10)
    const text = blockquote.dataset.sourceExcerpt
    if (!text) return

    const viewer = document.querySelector("[data-controller~='document-viewer']")
    if (!viewer) return

    viewer.dispatchEvent(new CustomEvent("highlight-source", {
      detail: {
        documentId,
        text,
        startOffset: Number.isNaN(startOffset) ? null : startOffset,
        endOffset: Number.isNaN(endOffset) ? null : endOffset
      }
    }))
  }
}
