// Mobile dashboard: tab strip switches Someday | Urgent | Calendar | Todos panels.
// Horizontal swipes change the calendar month (right = previous, left = next).
export const DashboardSwipe = {
  mounted() {
    this.panelsEl = this.el.querySelector("#m-dashboard-panels")
    this.calendarIndex = Number(this.el.dataset.dashboardCalendar ?? 1)
    this.panelIndex = this.calendarIndex
    this.touchStartX = null
    this.touchStartY = null
    this.swipeThreshold = 50
    this.onGoClick = this.onGoClick.bind(this)
    this.onTouchStart = this.onTouchStart.bind(this)
    this.onTouchEnd = this.onTouchEnd.bind(this)

    this.el.addEventListener("touchstart", this.onTouchStart, {passive: true})
    this.el.addEventListener("touchend", this.onTouchEnd, {passive: true})

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.addEventListener("click", this.onGoClick)
    })

    this.showPanel(this.panelIndex)
  },

  updated() {
    this.showPanel(this.panelIndex)
  },

  destroyed() {
    this.el.removeEventListener("touchstart", this.onTouchStart)
    this.el.removeEventListener("touchend", this.onTouchEnd)

    this.el.querySelectorAll("[data-dashboard-go]").forEach(btn => {
      btn.removeEventListener("click", this.onGoClick)
    })
  },

  onGoClick(event) {
    const index = Number(event.currentTarget.dataset.dashboardGo)
    if (Number.isNaN(index)) return

    this.panelIndex = index
    this.showPanel(index)
  },

  onTouchStart(event) {
    const touch = event.changedTouches[0]
    this.touchStartX = touch.clientX
    this.touchStartY = touch.clientY
  },

  onTouchEnd(event) {
    if (this.touchStartX == null || this.touchStartY == null) return

    const touch = event.changedTouches[0]
    const dx = touch.clientX - this.touchStartX
    const dy = touch.clientY - this.touchStartY

    this.touchStartX = null
    this.touchStartY = null

    if (Math.abs(dx) < this.swipeThreshold) return
    if (Math.abs(dx) < Math.abs(dy)) return
    if (this.panelIndex !== this.calendarIndex) return

    if (dx > 0) {
      this.pushEvent("prev_month", {})
    } else {
      this.pushEvent("next_month", {})
    }
  },

  showPanel(index) {
    this.panelsEl?.querySelectorAll("[data-dashboard-panel]").forEach(panel => {
      const active = Number(panel.dataset.dashboardPanel) === index
      panel.classList.toggle("hidden", !active)
    })

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