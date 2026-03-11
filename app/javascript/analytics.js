// Track page views for Turbo Drive soft navigations.
// The initial page load is already tracked by the gtag('config', ...) call
// in shared/_google_analytics.html.erb, so we skip it here.

let initialLoad = true

document.addEventListener("turbo:load", () => {
  if (initialLoad) {
    initialLoad = false
    return
  }

  if (typeof gtag === "function") {
    gtag("config", "G-KQLR3PQZ4W", {
      page_path: window.location.pathname + window.location.search
    })
  }
})
