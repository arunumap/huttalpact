import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput", "clearButton", "tab", "documentPanel", "documentText"]

  connect() {
    this.element.addEventListener("highlight-source", this.highlightSource.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("highlight-source", this.highlightSource.bind(this))
  }

  search() {
    const query = this.searchInputTarget.value.trim().toLowerCase()
    this.clearHighlights()
    this.toggleClearButton(query.length > 0)

    if (query.length < 2) return

    this.documentTextTargets.forEach(textEl => {
      const panel = textEl.closest("[data-document-viewer-target='documentPanel']")
      if (panel && panel.classList.contains("hidden")) return
      this.highlightTextInElement(textEl, query)
    })
  }

  clearSearch() {
    this.searchInputTarget.value = ""
    this.clearHighlights()
    this.toggleClearButton(false)
  }

  switchDocument({ params: { docIndex } }) {
    this.tabTargets.forEach((tab, idx) => {
      if (idx === docIndex) {
        tab.classList.add("bg-amber-100", "text-amber-700")
        tab.classList.remove("text-gray-500", "hover:text-gray-700", "hover:bg-gray-100")
      } else {
        tab.classList.remove("bg-amber-100", "text-amber-700")
        tab.classList.add("text-gray-500", "hover:text-gray-700", "hover:bg-gray-100")
      }
    })

    this.documentPanelTargets.forEach((panel, idx) => {
      panel.classList.toggle("hidden", idx !== docIndex)
    })

    this.clearHighlights()
  }

  highlightSource(event) {
    const { documentId, text } = event.detail
    this.clearHighlights()

    // Switch to the correct document tab if specified
    if (documentId) {
      const panelIndex = this.documentPanelTargets.findIndex(
        p => p.dataset.documentId === documentId
      )
      if (panelIndex >= 0) {
        const tab = this.tabTargets[panelIndex]
        if (tab) tab.click()
      }
    }

    // Find the visible panel
    const panel = documentId
      ? this.documentPanelTargets.find(p => p.dataset.documentId === documentId)
      : this.documentPanelTargets.find(p => !p.classList.contains("hidden"))
    if (!panel || !text) return

    // Search for the excerpt text in the document lines
    const normalizedText = text.trim().toLowerCase()
    const lines = panel.querySelectorAll("[data-line]")
    let found = false

    lines.forEach(line => {
      if (line.textContent.toLowerCase().includes(normalizedText.substring(0, 60))) {
        line.classList.add("bg-amber-100", "ring-2", "ring-amber-300", "rounded")
        if (!found) {
          line.scrollIntoView({ behavior: "smooth", block: "center" })
          found = true
        }
      }
    })
  }

  // Private

  toggleClearButton(show) {
    if (this.hasClearButtonTarget) {
      this.clearButtonTarget.classList.toggle("hidden", !show)
    }
  }

  clearHighlights() {
    this.element.querySelectorAll(".ring-amber-300").forEach(el => {
      el.classList.remove("bg-amber-100", "ring-2", "ring-amber-300", "rounded")
    })
    this.element.querySelectorAll("mark[data-search-highlight]").forEach(mark => {
      mark.replaceWith(document.createTextNode(mark.textContent))
    })
    // Normalize adjacent text nodes left behind by mark removal
    this.documentTextTargets.forEach(el => el.normalize())
  }

  highlightTextInElement(element, query) {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, null)
    const matches = []

    while (walker.nextNode()) {
      const node = walker.currentNode
      const text = node.textContent.toLowerCase()
      let pos = 0
      while ((pos = text.indexOf(query, pos)) !== -1) {
        matches.push({ node, pos, length: query.length })
        pos += query.length
      }
    }

    // Apply in reverse to preserve offsets
    matches.reverse().forEach(({ node, pos, length }) => {
      const range = document.createRange()
      range.setStart(node, pos)
      range.setEnd(node, pos + length)
      const mark = document.createElement("mark")
      mark.className = "bg-yellow-200 rounded px-0.5"
      mark.dataset.searchHighlight = ""
      range.surroundContents(mark)
    })
  }
}
