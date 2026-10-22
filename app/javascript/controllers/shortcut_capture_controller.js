import { Controller } from "@hotwired/stimulus"

const NAMED_KEYS = /^(Enter|Arrow(Up|Down|Left|Right)|F([1-9]|1[0-2]))$/

// Records a pressed chord as a binding string ("Ctrl/Cmd+Shift+S", order Ctrl/Cmd, Alt, Shift);
// bare keys and sequences are typed. Keys the server would reject get a hint instead.
export default class extends Controller {
  capture(event) {
    if (!(event.ctrlKey || event.metaKey || event.altKey)) return
    if (["Control", "Meta", "Alt", "Shift"].includes(event.key)) return

    event.preventDefault()
    // Alt rewrites the character on macOS, so read the physical key.
    const key = event.altKey && /^(Key|Digit)/.test(event.code) ? event.code.slice(-1) : event.key
    const named = NAMED_KEYS.test(key)
    if (!named && (key.length !== 1 || key === " ")) {
      this.element.setCustomValidity(`"${key}" can't be used; try a letter, digit, symbol, Enter, an arrow or F1-F12`)
      this.element.reportValidity()
      this.element.setCustomValidity("")
      return
    }

    this.element.setCustomValidity("")
    // Shift is implied by symbols ("?"), so only letters, digits and named keys record it.
    const shift = event.shiftKey && (named || /[a-z0-9]/i.test(key))
    const mods = [(event.ctrlKey || event.metaKey) && "Ctrl/Cmd", event.altKey && "Alt", shift && "Shift"]
    this.element.value = [...mods.filter(Boolean), named ? key : key.toUpperCase()].join("+")
  }
}
