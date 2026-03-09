import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer"]
  static values = { openId: String }

  connect() {
    this.hideTimers = new Map()
    this.drawerTargets.forEach((drawer) => this.resetDrawerState(drawer))

    if (this.hasOpenIdValue && this.openIdValue.length > 0) {
      this.openById(this.openIdValue)
    }
  }

  disconnect() {
    this.hideTimers.forEach((timerId) => clearTimeout(timerId))
    this.hideTimers.clear()
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    const drawerId = event.params.id
    if (!drawerId) return

    this.openById(drawerId)
  }

  close(event) {
    const drawer = event?.currentTarget?.closest("[data-drawer-id]") || this.currentDrawer
    if (!drawer) return

    this.animateClose(drawer)
    if (this.currentDrawer === drawer) this.currentDrawer = null
  }

  closeOnEscape(event) {
    if (event.key !== "Escape" || !this.currentDrawer) return

    event.preventDefault()
    this.close()
  }

  focusSource(event) {
    const sourceEl = event.currentTarget.closest("[data-source-excerpt]") || event.currentTarget
    const text = sourceEl.dataset.sourceExcerpt
    if (!text) return

    const documentId = sourceEl.dataset.sourceDocumentId
    const startOffset = Number.parseInt(sourceEl.dataset.sourceStart, 10)
    const endOffset = Number.parseInt(sourceEl.dataset.sourceEnd, 10)
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

  openById(drawerId) {
    const drawer = this.drawerTargets.find((target) => target.dataset.drawerId === drawerId)
    if (!drawer) return

    this.drawerTargets.forEach((target) => {
      if (target === drawer) return
      this.hideImmediately(target)
    })

    this.clearHideTimer(drawer)
    drawer.classList.remove("hidden")
    drawer.setAttribute("aria-hidden", "false")

    requestAnimationFrame(() => {
      this.backdropFor(drawer)?.classList.remove("opacity-0")
      this.backdropFor(drawer)?.classList.add("opacity-100")
      this.panelFor(drawer)?.classList.remove("translate-x-full")
      this.panelFor(drawer)?.classList.add("translate-x-0")
    })

    this.currentDrawer = drawer
    document.body.classList.add("overflow-hidden")

    const focusable = drawer.querySelector("button, [href], input, select, textarea")
    if (focusable) focusable.focus()
  }

  animateClose(drawer) {
    this.backdropFor(drawer)?.classList.remove("opacity-100")
    this.backdropFor(drawer)?.classList.add("opacity-0")
    this.panelFor(drawer)?.classList.remove("translate-x-0")
    this.panelFor(drawer)?.classList.add("translate-x-full")
    drawer.setAttribute("aria-hidden", "true")

    this.clearHideTimer(drawer)
    const timerId = setTimeout(() => {
      drawer.classList.add("hidden")
      this.hideTimers.delete(drawer)
      this.unlockBodyIfNeeded()
    }, this.animationDurationMs)
    this.hideTimers.set(drawer, timerId)
  }

  hideImmediately(drawer) {
    this.clearHideTimer(drawer)
    this.resetDrawerState(drawer)
    drawer.classList.add("hidden")
    drawer.setAttribute("aria-hidden", "true")
  }

  clearHideTimer(drawer) {
    const timerId = this.hideTimers.get(drawer)
    if (!timerId) return

    clearTimeout(timerId)
    this.hideTimers.delete(drawer)
  }

  resetDrawerState(drawer) {
    this.backdropFor(drawer)?.classList.remove("opacity-100")
    this.backdropFor(drawer)?.classList.add("opacity-0")
    this.panelFor(drawer)?.classList.remove("translate-x-0")
    this.panelFor(drawer)?.classList.add("translate-x-full")
  }

  backdropFor(drawer) {
    return drawer.querySelector("[data-drawer-backdrop]")
  }

  panelFor(drawer) {
    return drawer.querySelector("[data-drawer-panel]")
  }

  get animationDurationMs() {
    return 300
  }

  unlockBodyIfNeeded() {
    const visibleDrawer = this.drawerTargets.some((target) => !target.classList.contains("hidden"))
    if (!visibleDrawer) {
      document.body.classList.remove("overflow-hidden")
    }
  }
}
