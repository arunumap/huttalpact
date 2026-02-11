import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active", "inactive"]

  select(event) {
    const selectedPanel = event.currentTarget.dataset.tabsPanelParam

    // Update tab styles
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabsPanelParam === selectedPanel
      if (isActive) {
        this.inactiveClasses.forEach(c => tab.classList.remove(c))
        this.activeClasses.forEach(c => tab.classList.add(c))
        tab.classList.add("bg-amber-50")
      } else {
        this.activeClasses.forEach(c => tab.classList.remove(c))
        tab.classList.remove("bg-amber-50")
        this.inactiveClasses.forEach(c => tab.classList.add(c))
      }
    })

    // Show/hide panels
    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.tabsPanel !== selectedPanel)
    })
  }
}
