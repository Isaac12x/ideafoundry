import { Controller } from "@hotwired/stimulus"
import { mountEmojiGrid } from "lib/emoji_grid"

export default class extends Controller {
  static targets = ["emojiPanel", "imagePanel", "emojiTab", "imageTab", "kind", "emoji", "image", "preview", "grid"]
  static values = { emojiUrl: String }

  connect() {
    this.showEmojiTab()
    this.unmount = mountEmojiGrid(this.gridTarget, { url: this.emojiUrlValue, selected: this.emojiTarget.value, onPick: (emoji) => this.pick(emoji) })
  }

  disconnect() {
    this.unmount?.()
  }

  showEmojiTab(event) {
    event?.preventDefault()
    this.emojiPanelTarget.hidden = false
    this.imagePanelTarget.hidden = true
    this.emojiTabTarget.classList.add("is-active")
    this.imageTabTarget.classList.remove("is-active")
  }

  showImageTab(event) {
    event?.preventDefault()
    this.emojiPanelTarget.hidden = true
    this.imagePanelTarget.hidden = false
    this.emojiTabTarget.classList.remove("is-active")
    this.imageTabTarget.classList.add("is-active")
  }

  pick(emoji) {
    this.kindTarget.value = "emoji"
    this.emojiTarget.value = emoji
    this.previewTarget.textContent = emoji
    this.previewTarget.classList.remove("has-image")
    this.notifyChange()
  }

  imageChanged() {
    const file = this.imageTarget.files?.[0]
    if (!file) return

    this.kindTarget.value = "image"
    this.previewTarget.textContent = ""
    const image = document.createElement("img")
    image.src = URL.createObjectURL(file)
    image.alt = ""
    image.onload = () => URL.revokeObjectURL(image.src)
    this.previewTarget.appendChild(image)
    this.previewTarget.classList.add("has-image")
  }

  useDefault(event) {
    event.preventDefault()
    this.kindTarget.value = "default"
    this.emojiTarget.value = ""
    this.imageTarget.value = ""
    this.previewTarget.textContent = "📁"
    this.previewTarget.classList.remove("has-image")
    this.element.querySelectorAll(".kb-emoji-choice").forEach((button) => button.classList.remove("is-selected"))
    this.notifyChange()
  }

  // Hidden fields set from JS don't emit change; fire one so form-level autosave sees it
  notifyChange() {
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
