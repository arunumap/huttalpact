import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="multiselect-summary"
export default class extends Controller {
  static targets = ["checkbox", "menu", "pillContainer", "placeholder"]
  static values = { placeholder: String, visibleCount: Number }

  connect() {
    this.clickOutsideHandler = this.clickOutside.bind(this)
    this.escapeHandler = this.handleEscape.bind(this)
    this.render()
  }

  disconnect() {
    this.removeListeners()
  }

  toggle(event) {
    if (event.type === "keydown") {
      event.preventDefault()
    }

    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  sync() {
    this.render()
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()

    const checkbox = this.checkboxTargets.find((input) => input.value === String(event.params.value))
    if (!checkbox) return

    checkbox.checked = false
    this.render()
    this.close()
    this.element.closest("form")?.requestSubmit()
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.clickOutsideHandler)
    document.addEventListener("keydown", this.escapeHandler)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.removeListeners()
  }

  render() {
    const selected = this.checkboxTargets.filter((input) => input.checked)

    if (selected.length === 0) {
      this.pillContainerTarget.innerHTML = ""
      this.placeholderTarget.textContent = this.placeholderValue
      this.placeholderTarget.classList.remove("hidden")
      return
    }

    this.placeholderTarget.classList.add("hidden")
    const visibleCount = this.hasVisibleCountValue ? this.visibleCountValue : 3
    const visibleSelections = selected.slice(0, visibleCount)
    const hiddenCount = Math.max(selected.length - visibleSelections.length, 0)

    this.pillContainerTarget.innerHTML = visibleSelections.map((input) => this.pillMarkup(input)).join("") + this.moreMarkup(hiddenCount)
  }

  pillMarkup(input) {
    return `
      <button
        type="button"
        class="inline-flex max-w-40 shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-medium text-amber-800 ring-1 ring-amber-300"
        data-action="click->multiselect-summary#remove"
        data-multiselect-summary-value-param="${this.escapeAttribute(input.value)}"
      >
        <span class="truncate">${this.escapeHtml(input.dataset.label || input.value)}</span>
        <span aria-hidden="true" class="text-amber-700">&times;</span>
      </button>
    `
  }

  moreMarkup(hiddenCount) {
    if (hiddenCount <= 0) return ""

    return `
      <span class="inline-flex shrink-0 items-center rounded-full bg-gray-100 px-2.5 py-1 text-xs font-medium text-gray-700 ring-1 ring-gray-200">
        + ${hiddenCount} more
      </span>
    `
  }

  escapeHtml(value) {
    return value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  escapeAttribute(value) {
    return this.escapeHtml(String(value))
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  removeListeners() {
    document.removeEventListener("click", this.clickOutsideHandler)
    document.removeEventListener("keydown", this.escapeHandler)
  }
}
