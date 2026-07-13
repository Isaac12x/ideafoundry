import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["emojiPanel", "imagePanel", "emojiTab", "imageTab", "kind", "emoji", "image", "preview"]

  connect() {
    this.showEmojiTab()
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

  chooseEmoji(event) {
    event.preventDefault()
    const emoji = event.currentTarget.dataset.emoji
    this.kindTarget.value = "emoji"
    this.emojiTarget.value = emoji
    this.previewTarget.textContent = emoji
    this.previewTarget.classList.remove("has-image")
    this.element.querySelectorAll(".kb-emoji-choice").forEach((button) => {
      button.classList.toggle("is-selected", button === event.currentTarget)
    })
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
  }
}
