// Mobile dashboard: three full-width panels (Someday | Calendar | Todos).
// Native horizontal scroll + scroll-snap; preserves the active panel across
// LiveView patches and opens on the calendar panel by default.
export const DashboardSwipe = {
  mounted() {
    this.panelIndex = 1
    this.onScroll = this.onScroll.bind(this)
    this.el.addEventListener("scroll", this.onScroll, {passive: true})
    this.scrollToPanel(this.panelIndex, false)
  },

  updated() {
    this.scrollToPanel(this.panelIndex, false)
    this.updateDots(this.panelIndex)
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll)
  },

  onScroll() {
    const w = this.el.clientWidth
    if (!w) return

    this.panelIndex = Math.round(this.el.scrollLeft / w)
    this.updateDots(this.panelIndex)
  },

  scrollToPanel(index, smooth) {
    const w = this.el.clientWidth
    if (!w) return

    this.el.scrollTo({left: w * index, behavior: smooth ? "smooth" : "instant"})
    this.updateDots(index)
  },

  updateDots(index) {
    const dots = document.querySelectorAll("[data-dashboard-panel]")
    dots.forEach(dot => {
      const active = Number(dot.dataset.dashboardPanel) === index
      dot.classList.toggle("bg-primary", active)
      dot.classList.toggle("bg-base-content/20", !active)
    })
  },
}