import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
// Manages bulk selection of table rows with a "select all" checkbox,
// a bulk action toolbar, and form submission with selected IDs.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "toolbar", "count", "form"]

  connect() {
    this.updateToolbar()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.updateToolbar()
  }

  toggle() {
    this.updateToolbar()
  }

  updateToolbar() {
    const selected = this.selectedIds()
    const count = selected.length

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle("hidden", count === 0)
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${count} selected`
    }

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = count > 0 && count === this.checkboxTargets.length
      this.selectAllTarget.indeterminate = count > 0 && count < this.checkboxTargets.length
    }
  }

  submitBulk(event) {
    const action = event.currentTarget.dataset.bulkAction
    const confirmMessage = event.currentTarget.dataset.bulkConfirm
    const form = this.formTarget
    const selected = this.selectedIds()

    if (selected.length === 0) return

    if (confirmMessage && !window.confirm(confirmMessage)) return

    const isExportAction = action.includes("/bulk_export")
    form.dataset.turbo = isExportAction ? "false" : "true"

    if (!isExportAction) {
      this.markSelectedAsQueued(selected)
    }

    // Clear old hidden inputs
    form.querySelectorAll("input[name='ids[]']").forEach(el => el.remove())

    // Add selected IDs
    selected.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "ids[]"
      input.value = id
      form.appendChild(input)
    })

    // Set the action URL
    form.action = action
    form.requestSubmit()
  }

  markSelectedAsQueued(selectedIds) {
    const selectedSet = new Set(selectedIds)

    this.checkboxTargets.forEach(checkbox => {
      if (selectedSet.has(checkbox.value)) {
        checkbox.checked = false
        checkbox.disabled = true
      }
    })

    selectedIds.forEach(id => {
      this.element.querySelectorAll(`[data-contract-id="${id}"]`).forEach(el => {
        el.classList.add("opacity-60")

        const marker = el.querySelector("[data-bulk-select-marker]")
        if (!marker || marker.dataset.queued === "true") return

        marker.innerHTML = `<span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800">Queued for deletion</span>`
        marker.dataset.queued = "true"
      })
    })

    this.updateToolbar()
  }

  selectedIds() {
    return [...new Set(this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value))]
  }
}
