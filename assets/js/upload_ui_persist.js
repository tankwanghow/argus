const modalKey = id => `tugas:completion-modal:${id}`
const stepKey = id => `tugas:step-files:${id}`
const errorKey = id => `tugas:upload-error:${id}`

// A slot error can be raised while the socket is down (the size check runs when
// the camera returns mid-reconnect). Stash it so restore() can re-show it once
// the modal is rendered again — displayed purely client-side (no server event).
export function persistUploadError(dutyId, idPrefix, slot, message) {
  if (!dutyId) return
  try {
    sessionStorage.setItem(errorKey(dutyId), JSON.stringify({idPrefix, slot, message}))
  } catch (_e) {
    // ignore quota/serialisation errors
  }
}

export function clearUploadError(dutyId) {
  if (!dutyId) return
  sessionStorage.removeItem(errorKey(dutyId))
}

export function clearUploadPersist(dutyId) {
  if (!dutyId) return

  sessionStorage.removeItem(modalKey(dutyId))
  sessionStorage.removeItem(stepKey(dutyId))
  sessionStorage.removeItem(errorKey(dutyId))
}

export function showClientSlotError(idPrefix, slot, message) {
  const controls = document.querySelector(`[data-upload-slot-controls="${idPrefix}${slot}"]`)
  if (!controls) return

  const errorEl = controls.querySelector("[data-client-upload-error]")
  const errorRow = controls.querySelector("[data-client-upload-error-row]")
  const actionsEl = controls.querySelector("[data-upload-slot-actions]")

  if (errorEl) errorEl.textContent = message
  if (errorRow) errorRow.classList.remove("hidden")
  if (actionsEl) actionsEl.classList.add("hidden")
}

export function clearClientSlotError(idPrefix, slot) {
  const controls = document.querySelector(`[data-upload-slot-controls="${idPrefix}${slot}"]`)
  if (!controls) return

  const errorEl = controls.querySelector("[data-client-upload-error]")
  const errorRow = controls.querySelector("[data-client-upload-error-row]")
  const actionsEl = controls.querySelector("[data-upload-slot-actions]")

  if (errorEl) errorEl.textContent = ""
  if (errorRow) errorRow.classList.add("hidden")
  if (actionsEl) actionsEl.classList.remove("hidden")
}

export const UploadUiPersist = {
  mounted() {
    this.dutyId = this.el.dataset.dutyId

    this.handleEvent("persist_completion_modal", ({slot} = {}) => {
      if (!this.dutyId) return
      // Store the active slot so a remount restores the scoped view; "1" is
      // the sentinel for the unscoped (all required slots) view.
      sessionStorage.setItem(modalKey(this.dutyId), slot || "1")
      sessionStorage.removeItem(stepKey(this.dutyId))
    })

    this.handleEvent("clear_completion_modal_persist", () => {
      clearUploadPersist(this.dutyId)
    })

    this.handleEvent("persist_step_files", ({event_id}) => {
      if (!this.dutyId || !event_id) return
      sessionStorage.setItem(stepKey(this.dutyId), event_id)
      sessionStorage.removeItem(modalKey(this.dutyId))
    })

    this.handleEvent("clear_step_files_persist", () => {
      if (this.dutyId) sessionStorage.removeItem(stepKey(this.dutyId))
    })

    this.restore()
  },

  reconnected() {
    this.restore()
  },

  restore() {
    if (!this.dutyId) return

    const modalFlag = sessionStorage.getItem(modalKey(this.dutyId))
    const stepFlag = sessionStorage.getItem(stepKey(this.dutyId))

    let pendingError = null
    const errorRaw = sessionStorage.getItem(errorKey(this.dutyId))
    if (errorRaw) {
      try {
        pendingError = JSON.parse(errorRaw)
      } catch (_e) {
        pendingError = null
      }
    }

    // Re-show the stashed slot error once the restored modal has been patched in.
    const showErr = () => {
      if (!pendingError) return
      requestAnimationFrame(() => {
        const controls = document.querySelector(
          `[data-upload-slot-controls="${pendingError.idPrefix}${pendingError.slot}"]`
        )
        if (!controls) return

        showClientSlotError(pendingError.idPrefix, pendingError.slot, pendingError.message)
        clearUploadError(this.dutyId)
      })
    }

    if (modalFlag) {
      // "1" is the unscoped sentinel; any other value is the active slot name.
      const slot = modalFlag === "1" ? null : modalFlag
      this.pushEvent("restore_completion_modal", {slot}, showErr)
    } else if (stepFlag) {
      this.pushEvent("restore_step_files", {event_id: stepFlag}, showErr)
    } else {
      showErr()
    }
  },
}