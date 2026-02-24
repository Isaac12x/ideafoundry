import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "recipientsInput", "chipContainer",
    "triggerCard", "triggerCheckbox",
    "previewFrame",
    "eventCount", "digestCount"
  ]

  connect() {
    this.updateRecipientChips()
    this.updateGroupCounts()
  }

  // ── Recipients ──

  updateRecipientChips() {
    const input = this.recipientsInputTarget
    const container = this.chipContainerTarget
    const raw = input.value.trim()

    container.innerHTML = ""
    if (!raw) return

    raw.split(",").forEach(email => {
      const trimmed = email.trim()
      if (!trimmed) return

      const chip = document.createElement("span")
      chip.className = "recipient-chip"
      chip.textContent = trimmed
      container.appendChild(chip)
    })
  }

  // ── Trigger toggle ──

  toggleTrigger(event) {
    const checkbox = event.currentTarget
    const card = checkbox.closest(".ntf-card")

    if (checkbox.checked) {
      card.classList.add("ntf-card--active")
      card.classList.remove("ntf-card--inactive")
    } else {
      card.classList.remove("ntf-card--active")
      card.classList.add("ntf-card--inactive")
    }

    this.updateGroupCounts()
  }

  // ── Preset swatch ──

  selectPreset(event) {
    const label = event.currentTarget
    const card = label.closest(".ntf-card")
    const color = label.dataset.color

    // Deselect siblings
    card.querySelectorAll(".color-swatch").forEach(s => s.classList.remove("color-swatch--active"))
    label.classList.add("color-swatch--active")

    // Check the radio
    const radio = label.querySelector("input[type=radio]")
    if (radio) radio.checked = true

    // Update card accent
    card.style.setProperty("--card-accent", color)

    // Update preview bar
    const bar = card.querySelector(".email-preview-mini__bar")
    if (bar) bar.style.background = color
  }

  // ── Preview collapse ──

  togglePreview(event) {
    const btn = event.currentTarget
    const frame = btn.parentElement.querySelector("[data-email-settings-target='previewFrame']")
    if (!frame) return

    frame.classList.toggle("ntf-card__preview-frame--open")
    btn.classList.toggle("ntf-card__preview-toggle--open")
  }

  // ── Group counts ──

  updateGroupCounts() {
    const eventCards = this.triggerCardTargets.filter(c => c.dataset.triggerGroup === "event")
    const digestCards = this.triggerCardTargets.filter(c => c.dataset.triggerGroup === "digest")

    const eventActive = eventCards.filter(c => c.querySelector("input[type=checkbox]:checked")).length
    const digestActive = digestCards.filter(c => c.querySelector("input[type=checkbox]:checked")).length

    if (this.hasEventCountTarget) {
      this.eventCountTarget.textContent = `${eventActive}/${eventCards.length} active`
    }
    if (this.hasDigestCountTarget) {
      this.digestCountTarget.textContent = `${digestActive}/${digestCards.length} active`
    }
  }
}
