// Mobile dashboard: three full-width panels (Someday | Calendar | Todos).
// Tab strip jumps between panels; native scroll + snap still works.
export const DashboardSwipe = {
  mounted() {
    this.swipeEl = this.el.querySelector("#m-dashboard-swipe")
    this.panelIndex = 1
    this.onScroll = this.onScroll.bind(this)
    this.onGoClick = this.onGoClick.bind(this)

    if (this.swipeEl) {
      this.swipeEl.addEventListener("scroll", this.onScroll, {passive: true})
    }

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.addEventListener("click", this.onGoClick)
    })

    this.scrollToPanel(this.panelIndex, false)
  },

  updated() {
    this.scrollToPanel(this.panelIndex, false)
    this.updateTabs(this.panelIndex)
  },

  destroyed() {
    if (this.swipeEl) {
      this.swipeEl.removeEventListener("scroll", this.onScroll)
    }

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.removeEventListener("click", this.onGoClick)
    })
  },

  onGoClick(event) {
    const index = Number(event.currentTarget.dataset.dashboardGo)
    if (Number.isNaN(index)) return

    this.panelIndex = index
    this.scrollToPanel(index, true)
  },

  onScroll() {
    const w = this.swipeEl?.clientWidth
    if (!w) return

    this.panelIndex = Math.round(this.swipeEl.scrollLeft / w)
    this.updateTabs(this.panelIndex)
  },

  scrollToPanel(index, smooth) {
    const w = this.swipeEl?.clientWidth
    if (!w) return

    this.swipeEl.scrollTo({left: w * index, behavior: smooth ? "smooth" : "instant"})
    this.updateTabs(index)
  },

  updateTabs(index) {
    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      const active = Number(btn.dataset.dashboardGo) === index
      btn.classList.toggle("tab-active", active)
      btn.classList.toggle("font-bold", active)
    })
  },
}