import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput", "clearButton", "tab", "documentPanel", "documentText"]

  connect() {
    this.boundHighlightSource = this.highlightSource.bind(this)
    this.element.addEventListener("highlight-source", this.boundHighlightSource)
  }

  disconnect() {
    this.element.removeEventListener("highlight-source", this.boundHighlightSource)
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
    const { documentId, text, startOffset, endOffset } = event.detail || {}
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
    if (!panel) return

    // Prefer persisted source offsets when available.
    if (Number.isInteger(startOffset) && Number.isInteger(endOffset) && endOffset > startOffset) {
      if (this.highlightByOffsets(panel, startOffset, endOffset)) return
    }

    if (!text) return
    this.highlightByText(panel, text)
  }

  // Private

  highlightByOffsets(panel, startOffset, endOffset) {
    const lines = panel.querySelectorAll("[data-line]")
    let found = false

    lines.forEach(line => {
      const lineStart = Number.parseInt(line.dataset.docOffsetStart, 10)
      const lineEnd = Number.parseInt(line.dataset.docOffsetEnd, 10)
      if (Number.isNaN(lineStart) || Number.isNaN(lineEnd)) return

      const overlaps = lineStart <= endOffset && lineEnd >= startOffset
      if (!overlaps) return

      line.classList.add("bg-amber-100", "ring-2", "ring-amber-300", "rounded")
      if (!found) {
        line.scrollIntoView({ behavior: "smooth", block: "center" })
        found = true
      }
    })

    return found
  }

  highlightByText(panel, text) {
    const excerpt = this.normalizeForMatch(text)
    if (!excerpt) return

    const lines = panel.querySelectorAll("[data-line]")
    let found = false

    lines.forEach(line => {
      const lineText = this.normalizeForMatch(line.textContent)
      if (!this.lineMatchesExcerpt(lineText, excerpt)) return

      line.classList.add("bg-amber-100", "ring-2", "ring-amber-300", "rounded")
      if (!found) {
        line.scrollIntoView({ behavior: "smooth", block: "center" })
        found = true
      }
    })
  }

  lineMatchesExcerpt(lineText, excerptText) {
    if (!lineText || !excerptText) return false
    if (lineText.includes(excerptText)) return true

    const prefix = excerptText.substring(0, Math.min(excerptText.length, 80))
    if (prefix.length >= 12 && lineText.includes(prefix)) return true

    const excerptTokens = excerptText.split(" ").filter(token => token.length > 3)
    if (excerptTokens.length === 0) return false

    const overlapCount = excerptTokens.filter(token => lineText.includes(token)).length
    return overlapCount / excerptTokens.length >= 0.55
  }

  normalizeForMatch(text) {
    return text.toLowerCase().replace(/\s+/g, " ").trim()
  }

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
